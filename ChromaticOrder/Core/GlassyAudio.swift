//  Procedural soft-synth. Colors translate into notes inside the F#
//  Ionian scale (F# G# A# B C# D# E#) so the key stays consistent
//  everywhere — pickups, placements, button taps, the solve chord
//  and the ambient background loop all pull from the same palette
//  of pitches.
//
//  Mapping:
//    hue (0°..360°)  → Ionian degree (7 buckets around the wheel)
//    L   (0..1)      → octave offset (darker = lower)
//    c   (0..cMax)   → velocity / volume (more vivid = louder)
//
//  Two timbres:
//    .pickup / .place — soft mallet. Sine + faint 2× harmonic, 10ms
//              soft attack so there's no stick-tick, medium decay.
//              Pickups live an octave or two higher than places
//              (noteFor picks their octave band) so the two still
//              read as distinct gestures even though the tone is
//              shared.
//    .bloom  — pad bloom. Slow 90ms attack, single sine + gentle 2×,
//              long easing tail. Low register (F#2..F#3) for an
//              "ooooh" rather than a ping. Driven by `playBloom()`
//              (color-independent, random F# Phrygian pick) rather
//              than by the player's swatch color.
//
//  Solve chord layers two mallet chords (pickup octave + place
//  octave) so the "harmony of both" reads as a wide chord spanning
//  the player's palette up and down the staff.
//
//  Signal chain:
//    player pool → fanInMixer → delay → reverb → mainMixer → output
//
//  The delay unit is the "long, quiet echo" tail — low wet mix but
//  high feedback so each repeat is quieter than the last but rings
//  for several seconds. A low-pass on the feedback path rolls off
//  the high end of successive echoes so the tail feels warm, not
//  harsh.

import AVFoundation
import Foundation

@MainActor
final class GlassyAudio {
    static let shared = GlassyAudio()

    /// Master mute. When true, all play calls are no-ops and the
    /// engine is never started. Flip to re-enable.
    static var muted: Bool = false

    /// Background music gate. Toggled from the accessibility sheet.
    /// When true (and `muted` is false), a looping melodic phrase
    /// plays over both the menu and the game: F# → 3 random Ionian
    /// notes → F#, repeat. Keeps the game and menu feeling musical
    /// without requiring any extra interaction.
    static var musicEnabled: Bool = true {
        didSet {
            if musicEnabled {
                shared.startMusicIfNeeded()
            } else {
                shared.stopMusic()
            }
        }
    }

    enum Kind { case pickup, place, bloom, choir, glassHarmonica }

    private let engine = AVAudioEngine()
    /// Effects chain: delay first (long echoes), then reverb (air).
    /// The delay's feedback + low-pass gives the "quiet but long"
    /// tail the player asked for; reverb just adds a little room
    /// size so notes don't feel surgically dry.
    private let delay = AVAudioUnitDelay()
    private let reverb = AVAudioUnitReverb()
    /// Sums all player nodes into a single bus before the effects
    /// chain — effect units only accept one input. Without this
    /// mixer, attaching multiple players would throw on engine start.
    private let fanInMixer = AVAudioMixerNode()
    private let format: AVAudioFormat
    private let sampleRate: Double = 44_100
    private var playerPool: [AVAudioPlayerNode] = []
    private let poolSize = 10
    private var nextPlayerIdx = 0
    private var started = false
    private var cache: [CacheKey: AVAudioPCMBuffer] = [:]

    /// Wall-clock anchor for the bloom tempo grid. Set the first time
    /// the engine starts; all bloom playbacks snap to `gridSec`
    /// intervals measured from here so consecutive random-bloom hits
    /// land on a shared beat grid instead of wherever the user
    /// happened to tap.
    private var tempoAnchor: Date?
    /// 16th note at ~110 BPM (60 / 110 / 4 ≈ 0.136s). Delay between
    /// a button press and the snapped beat is at most ~136ms, still
    /// responsive, but voicings across multiple presses interlock.
    private let gridSec: Double = 60.0 / 110.0 / 4.0

    /// Background-music loop. Non-nil while the melodic phrase loop
    /// is active. Cancelled when music is turned off or when the
    /// engine fails to start.
    private var musicTask: Task<Void, Never>?

    private struct CacheKey: Hashable {
        let semitone: Int
        let kind: Int   // 0 pickup, 1 place, 2 bloom
    }

    private init() {
        guard let fmt = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate, channels: 1
        ) else {
            fatalError("AVAudioFormat init failed")
        }
        self.format = fmt

        // Delay: 420ms between echoes, 72% feedback so each echo is
        // ~28% quieter than the last, low-pass the feedback path at
        // 3.2 kHz so the tail warms as it fades. 16% wet mix keeps
        // the echo subtle — the dry note still reads as the primary
        // event.
        delay.delayTime = 0.42
        delay.feedback = 72
        delay.lowPassCutoff = 3200
        delay.wetDryMix = 16

        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = 14

        engine.attach(fanInMixer)
        engine.attach(delay)
        engine.attach(reverb)
        engine.connect(fanInMixer, to: delay, format: format)
        engine.connect(delay, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)

        for _ in 0..<poolSize {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: fanInMixer, format: format)
            playerPool.append(p)
        }
    }

    // ─── Public ─────────────────────────────────────────────────────

    func play(_ color: OKLCh, kind: Kind) {
        if Self.muted { return }
        ensureStarted()
        let semitone = noteFor(color: color, kind: kind)
        let buffer = buffer(for: semitone, kind: kind)
        let velocity = 0.55 + 0.45 * color.c / OK.cMax
        playOneShot(buffer: buffer, volume: Float(clamp(velocity, 0.55, 1.0)))
    }

    /// Solved-puzzle sound — F# tonic stacked at three octaves
    /// (F#2 / F#3 / F#4). Not a harmonic "chord" but a single note
    /// thickened with octave doublings; reads as one strong tonic
    /// with body. Colors no longer determine the pitches (which
    /// used to produce a wide-interval chord that varied by puzzle);
    /// the reward sound is now the same grounded F# every time.
    func playSolveChord(colors: [OKLCh]) {
        if Self.muted { return }
        ensureStarted()
        let semitones = [42, 54, 66]   // F#2, F#3, F#4
        let buffer = synthesizeChord(semitones: semitones,
                                      kind: .place, duration: 4.2)
        playOneShot(buffer: buffer, volume: 0.82)
    }

    /// Ambient pad bloom. Ignores the caller's color — instead picks
    /// a random F# Ionian voicing each time: mostly a single note
    /// (tonic F# biased), sometimes two- or three-note chords, always
    /// within the key. Playback is quantized to a shared 16th-note
    /// grid so consecutive presses interlock rhythmically instead of
    /// arriving at arbitrary moments.
    func playBloom() {
        if Self.muted { return }
        ensureStarted()
        let semis = randomBloomSemitones()
        let buffer = synthesizeChord(semitones: semis,
                                      kind: .bloom, duration: 1.9)
        playOnGrid(buffer: buffer, volume: 0.60)
    }

    private func randomBloomSemitones() -> [Int] {
        // Voicing probability — a mix of singles and chords. Heavier
        // on chords than the prior pass so consecutive taps produce
        // clear variety (user feedback: "I want random notes and
        // there are none currently" — the range was too low to be
        // audible; chord frequency boosted here too so the variety
        // is easy to hear).
        let roll = Double.random(in: 0..<1)
        let count = roll < 0.40 ? 1 : (roll < 0.75 ? 2 : 3)
        var semis = Set<Int>()
        var tries = 0
        while semis.count < count && tries < 12 {
            tries += 1
            let isFirst = semis.isEmpty
            let degreeIdx: Int
            // Bias the first note toward F# (tonic) so the
            // "randomness" feels like it's orbiting the home note
            // rather than drifting through the scale at random.
            if isFirst && Double.random(in: 0..<1) < 0.40 {
                degreeIdx = 0
            } else {
                degreeIdx = Int.random(in: 0..<Self.ionianSemitones.count)
            }
            let degree = Self.ionianSemitones[degreeIdx]
            let octaveOffset = Int.random(in: 0..<2) * 12
            // Two octaves (F#2..F#3 + degree) — matches the .bloom
            // band in noteFor; the top octave is excluded to keep
            // every voicing in the warm register.
            semis.insert(42 + octaveOffset + degree)
        }
        return Array(semis).sorted()
    }

    // ─── Background music loop ──────────────────────────────────────

    /// Starts the background music loop if music is enabled and the
    /// engine is running. Safe to call multiple times — an existing
    /// task is left in place. Idempotent entry points make wiring
    /// onAppear / onChange straightforward for the caller.
    func startMusicIfNeeded() {
        if Self.muted { return }
        if !Self.musicEnabled { return }
        if musicTask != nil { return }
        ensureStarted()
        guard started else { return }
        musicTask = Task { @MainActor [weak self] in
            await self?.runMusicLoop()
        }
    }

    func stopMusic() {
        musicTask?.cancel()
        musicTask = nil
    }

    /// Phrase: F# (tonic) → 3 random Ionian degrees → F# (tonic),
    /// repeating. Each note is one beat at ~55 BPM (halved from the
    /// earlier 110 BPM for a slower, more meditative feel —
    /// ~1090ms per note). The phrase loops indefinitely; cancelling
    /// the task stops it between notes. Timbre per note is chosen
    /// at random from three ambient voices (pad bloom, choir,
    /// glass harmonica) so repeats never sound identical.
    private func runMusicLoop() async {
        let beatNs: UInt64 = UInt64(60.0 / 55.0 * 1_000_000_000)
        let timbres: [Kind] = [.bloom, .choir, .glassHarmonica]
        while !Task.isCancelled && Self.musicEnabled && !Self.muted {
            // Five-note phrase: start on tonic, wander three, return
            // to tonic before repeating. Notes span F#3..F#4 +
            // degree — just two octaves so the melody stays in its
            // ambient register and never climbs up to F#5.
            let tonic = 54            // F#3
            var phrase: [Int] = [tonic]
            for _ in 0..<3 {
                let deg = Self.ionianSemitones.randomElement() ?? 0
                let oct = Int.random(in: 0..<2) * 12
                phrase.append(tonic + oct + deg)
            }
            phrase.append(tonic)

            for semi in phrase {
                if Task.isCancelled || !Self.musicEnabled || Self.muted { return }
                // Route through the buffer cache so the 1.6-2.3s
                // ambient samples aren't re-synthesized every note.
                let kind = timbres.randomElement() ?? .bloom
                let buffer = self.buffer(for: semi, kind: kind)
                // Low background volume — must sit well underneath
                // the interactive sounds (bloom button-hits, mallet
                // pickup/place). 0.26 reads as "present but quiet."
                playOneShot(buffer: buffer, volume: 0.26)
                try? await Task.sleep(nanoseconds: beatNs)
            }
        }
    }

    // ─── Mapping: OKLCh → F# Phrygian note ─────────────────────────

    /// F# Ionian (major) scale — semitones from F#. Seven degrees,
    /// the standard consonant palette: F# G# A# B C# D# E#.
    private static let ionianSemitones: [Int] = [0, 2, 4, 5, 7, 9, 11]

    private func noteFor(color: OKLCh, kind: Kind) -> Int {
        let h = color.h.truncatingRemainder(dividingBy: 360)
        let hNorm = h < 0 ? h + 360 : h
        let degreeIdx = min(
            Self.ionianSemitones.count - 1,
            Int(hNorm / (360.0 / Double(Self.ionianSemitones.count)))
        )
        let degree = Self.ionianSemitones[degreeIdx]
        let lNorm = clamp((color.L - OK.lMin) / (OK.lMax - OK.lMin), 0, 1)
        // Per-kind base MIDI + octave span. Each kind sits in its
        // own register so the timbres don't fight each other when
        // played simultaneously.
        let (baseMidi, octaveSpan): (Int, Int)
        switch kind {
        // Top octave excluded — dropped from 3 to 2 so L drives
        // notes into F#2..F#3 only. F#4+ was flagged as too high,
        // but removing L differentiation entirely felt too flat.
        case .pickup, .place: baseMidi = 42; octaveSpan = 2   // F#2..F#3
        case .bloom, .choir, .glassHarmonica:
            baseMidi = 42; octaveSpan = 2                     // F#2..F#3
        }
        let octaveOffset = Int(lNorm * Double(octaveSpan) * 0.9999) * 12
        return baseMidi + octaveOffset + degree
    }

    private func frequency(semitone: Int) -> Double {
        440.0 * pow(2.0, Double(semitone - 69) / 12.0)
    }

    // ─── Synthesis ──────────────────────────────────────────────────

    private func buffer(for semitone: Int, kind: Kind) -> AVAudioPCMBuffer {
        let k: Int
        switch kind {
        case .pickup:         k = 0
        case .place:          k = 1
        case .bloom:          k = 2
        case .choir:          k = 3
        case .glassHarmonica: k = 4
        }
        let key = CacheKey(semitone: semitone, kind: k)
        if let cached = cache[key] { return cached }
        let freq = frequency(semitone: semitone)
        let buffer: AVAudioPCMBuffer
        switch kind {
        case .pickup, .place: buffer = synthesizeSoftMallet(frequency: freq)
        case .bloom:          buffer = synthesizePadBloom(frequency: freq)
        case .choir:          buffer = synthesizeChoir(frequency: freq)
        case .glassHarmonica: buffer = synthesizeGlassHarmonica(frequency: freq)
        }
        cache[key] = buffer
        return buffer
    }

    /// Soft mallet: sine + faint 2nd, with a 10ms attack that hides
    /// the stick-tick, and a medium decay. Warm, un-sparkly — reads
    /// as "color set down" rather than "color dropped." 2× harmonic
    /// kept low (0.08) to prevent brightness at the top of the range.
    private func synthesizeSoftMallet(frequency: Double) -> AVAudioPCMBuffer {
        let duration: Double = 1.10
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: frameCount) else {
            fatalError("mallet buffer alloc failed")
        }
        buffer.frameLength = frameCount
        let ptr = buffer.floatChannelData![0]
        let twoPi = 2.0 * Double.pi
        let attackSec = 0.010
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let f1 =        sin(twoPi * frequency * 1.0 * t)
            let f2 = 0.08 * sin(twoPi * frequency * 2.0 * t)
            let voice = (f1 + f2) * 0.88
            let attack = min(1.0, t / attackSec)
            let decay = exp(-t * 2.2)
            ptr[i] = Float(voice * attack * decay * 0.16)
        }
        return buffer
    }

    /// Choir "ah": sine fundamental + small 3× and 5× harmonics for
    /// a vowel-like body, slow 120ms attack, long sustained decay.
    /// Reads as a soft massed voice — more texture than the pure
    /// pad bloom, still ambient.
    private func synthesizeChoir(frequency: Double) -> AVAudioPCMBuffer {
        let duration: Double = 2.20
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: frameCount) else {
            fatalError("choir buffer alloc failed")
        }
        buffer.frameLength = frameCount
        let ptr = buffer.floatChannelData![0]
        let twoPi = 2.0 * Double.pi
        let attackSec = 0.120
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let f1 =        sin(twoPi * frequency * 1.0 * t)
            let f3 = 0.18 * sin(twoPi * frequency * 3.0 * t)
            let f5 = 0.08 * sin(twoPi * frequency * 5.0 * t)
            let voice = (f1 + f3 + f5) * 0.78
            let attack = min(1.0, t / attackSec)
            let decay = exp(-t * 0.80)
            ptr[i] = Float(voice * attack * decay * 0.17)
        }
        return buffer
    }

    /// Glass harmonica: pure sine with a slow 180ms swell and a
    /// gentle 3 Hz vibrato on pitch (phase-accumulated so the freq
    /// modulation stays clean). Ethereal, almost vocal quality —
    /// the "wet finger on a glass rim" tone.
    private func synthesizeGlassHarmonica(frequency: Double) -> AVAudioPCMBuffer {
        let duration: Double = 2.30
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: frameCount) else {
            fatalError("glass harmonica buffer alloc failed")
        }
        buffer.frameLength = frameCount
        let ptr = buffer.floatChannelData![0]
        let twoPi = 2.0 * Double.pi
        let attackSec = 0.180
        let vibRate: Double = 3.0       // Hz
        let vibDepth: Double = 0.006    // ±0.6% pitch
        var phase = 0.0
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let instFreq = frequency * (1.0 + vibDepth * sin(twoPi * vibRate * t))
            phase += twoPi * instFreq / sampleRate
            let f1 =        sin(phase)
            let f2 = 0.05 * sin(2.0 * phase)
            let voice = (f1 + f2) * 0.78
            let attack = min(1.0, t / attackSec)
            let decay = exp(-t * 0.70)
            ptr[i] = Float(voice * attack * decay * 0.20)
        }
        return buffer
    }

    /// Pad bloom: slow 90ms attack so the note swells in, single sine
    /// + gentle 2×, very long soft tail. No transient spike — reads
    /// as an ambient rise, suited to menu-style button presses.
    private func synthesizePadBloom(frequency: Double) -> AVAudioPCMBuffer {
        let duration: Double = 1.60
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: frameCount) else {
            fatalError("bloom buffer alloc failed")
        }
        buffer.frameLength = frameCount
        let ptr = buffer.floatChannelData![0]
        let twoPi = 2.0 * Double.pi
        let attackSec = 0.090
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let f1 =        sin(twoPi * frequency * 1.0 * t)
            let f2 = 0.22 * sin(twoPi * frequency * 2.0 * t)
            let voice = (f1 + f2) * 0.82
            let attack = min(1.0, t / attackSec)
            let decay = exp(-t * 1.2)
            ptr[i] = Float(voice * attack * decay * 0.16)
        }
        return buffer
    }

    private func synthesizeChord(semitones: [Int], kind: Kind,
                                  duration: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: frameCount) else {
            fatalError("chord buffer alloc failed")
        }
        buffer.frameLength = frameCount
        let ptr = buffer.floatChannelData![0]
        let voices = max(1, semitones.count)
        let voiceNorm = 1.0 / sqrt(Double(voices))
        // Stagger per kind — water drops arrive a beat quicker than
        // mallets. The small per-voice onset gap keeps the chord
        // from cracking in as one hard edge.
        let staggerStep: Double = kind == .pickup ? 0.025 : 0.045
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            var sample = 0.0
            for (vIdx, semitone) in semitones.enumerated() {
                let tLocal = t - Double(vIdx) * staggerStep
                guard tLocal > 0 else { continue }
                let freq = frequency(semitone: semitone)
                sample += voiceSample(t: tLocal, freq: freq, kind: kind)
            }
            ptr[i] = Float(sample * voiceNorm * 0.32)
        }
        return buffer
    }

    /// Single-voice sample for the chord synth — stateless per-time
    /// function so we can iterate frames and sum voices without
    /// carrying phase accumulators across the outer loop. Glass
    /// harmonica's vibrato isn't stateless so it falls back to a
    /// non-vibrato sine here; good enough inside a chord.
    private func voiceSample(t: Double, freq: Double, kind: Kind) -> Double {
        let twoPi = 2.0 * Double.pi
        switch kind {
        case .pickup, .place:
            let f1 =        sin(twoPi * freq * 1.0 * t)
            let f2 = 0.08 * sin(twoPi * freq * 2.0 * t)
            let attack = min(1.0, t / 0.010)
            let decay = exp(-t * 1.1)
            return (f1 + f2) * attack * decay
        case .bloom:
            let f1 =        sin(twoPi * freq * 1.0 * t)
            let f2 = 0.22 * sin(twoPi * freq * 2.0 * t)
            let attack = min(1.0, t / 0.090)
            let decay = exp(-t * 0.8)
            return (f1 + f2) * attack * decay
        case .choir:
            let f1 =        sin(twoPi * freq * 1.0 * t)
            let f3 = 0.18 * sin(twoPi * freq * 3.0 * t)
            let f5 = 0.08 * sin(twoPi * freq * 5.0 * t)
            let attack = min(1.0, t / 0.120)
            let decay = exp(-t * 0.8)
            return (f1 + f3 + f5) * attack * decay
        case .glassHarmonica:
            let f1 =        sin(twoPi * freq * 1.0 * t)
            let f2 = 0.05 * sin(twoPi * freq * 2.0 * t)
            let attack = min(1.0, t / 0.180)
            let decay = exp(-t * 0.7)
            return (f1 + f2) * attack * decay
        }
    }

    // ─── Engine lifecycle + playback ────────────────────────────────

    private func ensureStarted() {
        guard !started else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default,
                                     options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
            tempoAnchor = Date()
            started = true
        } catch {
            started = false
        }
    }

    private func playOneShot(buffer: AVAudioPCMBuffer, volume: Float) {
        guard started else { return }
        let player = playerPool[nextPlayerIdx]
        nextPlayerIdx = (nextPlayerIdx + 1) % poolSize
        if player.isPlaying { player.stop() }
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    /// Plays a buffer on the shared tempo grid — defers the one-shot
    /// by however long it takes to reach the next grid tick, so all
    /// grid-snapped playbacks interlock. Pure play-immediately path
    /// kicks in when the press already falls within ~5ms of a tick.
    private func playOnGrid(buffer: AVAudioPCMBuffer, volume: Float) {
        guard started, let anchor = tempoAnchor else { return }
        let elapsed = Date().timeIntervalSince(anchor)
        let snapped = ceil(elapsed / gridSec) * gridSec
        let delay = max(0, snapped - elapsed)
        if delay < 0.005 {
            playOneShot(buffer: buffer, volume: volume)
            return
        }
        // Claim the player slot now so subsequent rapid taps rotate
        // through the pool rather than fighting for the same node.
        let player = playerPool[nextPlayerIdx]
        nextPlayerIdx = (nextPlayerIdx + 1) % poolSize
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.started else { return }
            if player.isPlaying { player.stop() }
            player.volume = volume
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    private func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
        min(max(v, lo), hi)
    }
}
