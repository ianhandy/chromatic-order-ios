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
            if isUnderTest { return }
            if musicEnabled {
                shared.startMusicIfNeeded()
            } else {
                shared.stopMusic()
            }
        }
    }

    /// In-game sound effects gate (swatch pickup/place clicks, solve
    /// chord, menu bloom). Independent of `musicEnabled` so players
    /// can silence one without the other.
    static var sfxEnabled: Bool = true

    /// True when the app is hosted under XCTest — audio engine graph
    /// isn't built (see `init`) and every entry point short-circuits
    /// so the simulator's audio server can't deadlock the test runner.
    private static let isUnderTest: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

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
    /// Dedicated player for the looping background hum. Mounted once
    /// when `startHum()` is first called; its buffer is a 4-beat
    /// drone at F#1 that loops indefinitely. Volume is modulated
    /// live to duck up on menu ripples and back down again.
    private var humPlayer: AVAudioPlayerNode? = nil
    private var humBuffer: AVAudioPCMBuffer? = nil
    private static let humBaseVolume: Float = 0.06
    private static let humBoostVolume: Float = 0.22
    private var humDecayTask: Task<Void, Never>? = nil
    /// Last semitone dispatched from `play(_:kind:)`. The anti-repeat
    /// rule consults this so non-F# notes don't immediately repeat
    /// themselves.
    private var lastPlaySemitone: Int? = nil
    /// Set whenever the music loop plays more than one note
    /// simultaneously (main + harmony stack inside `playBeatNote`).
    /// `maybePlaySixteenthGrace` consults this and skips the next
    /// 16th-note grace slot so a chord isn't immediately followed by
    /// a fluttery off-beat single note — the chord needs room to
    /// breathe before the next event lands.
    private var lastBeatWasChord: Bool = false
    /// Chord currently anchoring the bass line. Updated at the start
    /// of each beat inside `runMusicLoop`; nil when the music loop
    /// isn't running (cold launch, music disabled, etc.).
    ///
    /// Pickup / place SFX read this so each drag event lands on a
    /// pitch that's in-harmony with whatever the backing is playing —
    /// pickups get the current chord's 3rd, placements get its root.
    /// If a pickup and place straddle a beat boundary, each reads the
    /// chord that was active at ITS moment, which is the behavior
    /// the player hears as "pitch matched the music."
    private var currentBassChord: MusicChord? = nil
    private let poolSize = 24
    private var nextPlayerIdx = 0
    private var started = false
    private var cache: [CacheKey: AVAudioPCMBuffer] = [:]
    /// LRU access order — most-recently-used at the end.
    private var cacheOrder: [CacheKey] = []
    /// Max cached buffers. 128 entries × ~200-400 KB ≈ 25-50 MB.
    private let cacheCapacity = 128

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
    /// Quarter note at ~110 BPM — used by the solve-squish timing.
    private let quarterSec: Double = 60.0 / 110.0

    /// Seconds until the next quarter-note beat boundary on the
    /// shared tempo grid. Returns 0 if no anchor is set.
    func secondsToNextQuarterBeat() -> Double {
        guard let anchor = tempoAnchor else { return 0 }
        let elapsed = Date().timeIntervalSince(anchor)
        let snapped = ceil(elapsed / quarterSec) * quarterSec
        return max(0, snapped - elapsed)
    }

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

        // Under XCTest, skip the engine graph construction. Building
        // `engine.mainMixerNode` synchronously RPCs the simulator's
        // audio server and sporadically times out → SIGABRT before the
        // first test assertion runs. The solvability audit doesn't
        // touch audio, so stubbing out the graph here costs nothing.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        // iOS tears down AVAudioEngine on app-backgrounding interruption
        // and on audio-route / sample-rate changes. Without these
        // observers, the first play() call after resume crashes because
        // the engine's graph is stale. handleInterruption / handleConfig
        // bounce the engine and restart music.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] notif in
            // Synchronous on .main — no Task enqueue — so `started`
            // flips to false before the music loop's next suspension
            // point resumes. The old `Task { @MainActor }` wrapper let
            // the loop wake and call player.play() on a torn-down
            // engine before the handler ran, crashing via NSException.
            MainActor.assumeIsolated { self?.handleInterruption(notif) }
        }
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        }

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
        // Headroom: fan-in mixer pre-effects is scaled down so
        // summed voices (bass + melody + F# triad emphasis + pickup/
        // place chord tones + grace notes) don't exceed 1.0 at the
        // output stage and clip. 0.70 leaves ~30% headroom — enough
        // for a typical 4-5 simultaneous voice peak without audible
        // clipping / popping.
        fanInMixer.outputVolume = 0.70
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
        if Self.muted || !Self.sfxEnabled { return }
        ensureStarted()
        var semitone = noteFor(color: color, kind: kind)
        // Octave jitter — 30% of taps shift up or down an octave so
        // the same hue bucket doesn't always map to an identical
        // note. Adds real ear-variety without breaking the
        // color-to-pitch mapping's meaning. Clamped to the usable
        // register so low colors don't sink below F#1 and highs
        // don't climb above F#4.
        if Double.random(in: 0..<1) < 0.30 {
            let up = Bool.random()
            let jittered = semitone + (up ? 12 : -12)
            if jittered >= 30 && jittered <= 78 { semitone = jittered }
        }
        // Anti-repeat rule: non-F# notes don't get to play twice in
        // a row. If this note matches the last one played AND it's
        // not the tonic, nudge it to a different scale degree in the
        // same octave (and never to F#, unless the last was F#).
        // F# itself is exempt — repeated tonics are musically fine.
        let originalDegree = ((semitone % 12) + 12) % 12
        if let last = lastPlaySemitone, last == semitone, originalDegree != 0 {
            semitone = nudgeAwayFromRepeat(semitone: semitone)
        }
        lastPlaySemitone = semitone
        let buffer = buffer(for: semitone, kind: kind)
        // Per-placement velocity dialed down from the 0.55-1.0 range
        // to 0.35-0.65. Rapid cell placements were stacking into a
        // harsh peak; these sit under the music bed more comfortably.
        let velocity = 0.35 + 0.30 * color.c / OK.cMax
        playOneShot(buffer: buffer, volume: Float(clamp(velocity, 0.35, 0.65)))
        postNotePlayed(semitone: semitone)
    }

    /// Pick a non-F# scale degree in the same octave, distinct from
    /// the input semitone. `ionianSemitones` are offsets from F#
    /// (not C), so we anchor to the nearest F# at or below the
    /// input — anchoring to the C octave would push candidates out
    /// of the F# major scale.
    private func nudgeAwayFromRepeat(semitone: Int) -> Int {
        // MIDI semitone 6 = F#0. Step up in 12-semitone octaves
        // from there to find the F# at or below `semitone`.
        let fSharpBase = ((semitone - 6) / 12) * 12 + 6
        let currentOffset = semitone - fSharpBase
        // Drop F# (degree 0) so we never force a non-tonic into
        // tonic, and drop the current degree so we actually change.
        let candidates = Self.ionianSemitones.filter { $0 != 0 && $0 != currentOffset }
        let pick = candidates.randomElement() ?? 2
        return fSharpBase + pick
    }

    /// Solved-puzzle sound — voiced from whatever chord the music
    /// loop is currently on so the reward lands consonantly over the
    /// backing track. Falls back to I (F# major) when music is off.
    func playSolveChord(colors: [OKLCh]) {
        if Self.muted || !Self.sfxEnabled { return }
        ensureStarted()
        let chord = currentBassChord ?? .I
        let degrees = chord.chordDegrees       // [root, 3rd, 5th] as scale-degree indices
        let tonic = 54                          // F#3
        // Semitone offsets from F# for each chord tone.
        let rootOff  = Self.ionianSemitones[degrees[0]]
        var thirdOff = Self.ionianSemitones[degrees[1]]
        var fifthOff = Self.ionianSemitones[degrees[2]]
        // Ensure 3rd and 5th sit above the root within a single
        // octave so the voicing stacks upward.
        if thirdOff <= rootOff { thirdOff += 12 }
        if fifthOff <= rootOff { fifthOff += 12 }
        // Spread the triad across ~2 octaves, each voice randomly
        // picking one of two adjacent registers so the chord's sonic
        // "color" rotates without changing harmony.
        let lowRoot  = tonic + rootOff - 12 + (Bool.random() ? 0 : 12)
        let midRoot  = tonic + rootOff + (Bool.random() ? 0 : 12)
        let third    = tonic + thirdOff + (Bool.random() ? 0 : -12)
        let fifth    = tonic + fifthOff + (Bool.random() ? 0 : -12)
        let topRoot  = tonic + rootOff + (Bool.random() ? 12 : 24)
        let semitones = [lowRoot, midRoot, third, fifth, topRoot]
        let buffer = synthesizeChord(semitones: semitones,
                                      kind: .place, duration: 4.2)
        playOneShot(buffer: buffer, volume: 0.55)
        postNotePlayed(semitone: semitones.first ?? 42)
    }

    /// Ambient pad bloom. Ignores the caller's color — instead picks
    /// a random F# Ionian voicing each time: single-note voicings
    /// walk the scale (tonic-biased), and any multi-note voicing is
    /// drawn from a major triad (I, IV, or V of F# major) so every
    /// stacked harmony stays unambiguously major. Playback is
    /// quantized to a shared 16th-note grid so consecutive presses
    /// interlock rhythmically.
    func playBloom() {
        if Self.muted || !Self.sfxEnabled { return }
        ensureStarted()
        let semis = randomBloomSemitones()
        let buffer = synthesizeChord(semitones: semis,
                                      kind: .bloom, duration: 1.9)
        playOnGrid(buffer: buffer, volume: 0.60)
        postNotePlayed(semitone: semis.first ?? 42)
    }

    /// Short balloon-pop sample. Synthesized on the fly as a brief
    /// (~110 ms) band-passed noise burst with a steep envelope — reads
    /// as a rubbery "pop" without needing a bundled asset. Not
    /// grid-snapped because tutorial pops fire in response to player
    /// taps and should sound immediate, not quantized.
    func playPop() {
        if Self.muted || !Self.sfxEnabled { return }
        ensureStarted()
        let buffer = synthesizePopBuffer()
        playOneShot(buffer: buffer, volume: 0.75)
    }

    private func synthesizePopBuffer() -> AVAudioPCMBuffer {
        let sr = sampleRate
        let durationSec = 0.18
        let sampleCount = AVAudioFrameCount(sr * durationSec)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: sampleCount
        ) else {
            fatalError("pop buffer alloc failed")
        }
        buffer.frameLength = sampleCount
        let channels = Int(format.channelCount)
        let frames = Int(sampleCount)

        // Tail fade-out (last 15 ms) to guarantee silence at the
        // buffer boundary — avoids a click when the scheduler stops.
        let tailFadeSec = 0.015
        let tailFadeFrames = Double(frames) - tailFadeSec * sr

        // Filter state for band-shaping the body noise.
        var lpPrev: Double = 0
        var hpPrev: Double = 0
        var hpIn: Double = 0
        let lpCoeff = 0.45   // wider passband than before
        let hpCoeff = 0.90

        for ch in 0..<channels {
            let ptr = buffer.floatChannelData![ch]
            for i in 0..<frames {
                let t = Double(i) / sr

                // Layer 1 — Initial crack: broadband noise burst,
                // instant attack, ~8 ms half-life. The snap of rubber.
                let crackEnv = exp(-t / 0.008)
                let crackNoise = Double.random(in: -1...1)
                let crack = crackNoise * crackEnv * 0.85

                // Layer 2 — Body: band-filtered noise, fast decay.
                // The air-release hiss after the snap.
                let bodyAttack = min(1.0, t / 0.001)
                let bodyDecay = exp(-t / 0.040)
                let bodyEnv = bodyAttack * bodyDecay
                let rawNoise = Double.random(in: -1...1)
                let lp = lpPrev + lpCoeff * (rawNoise - lpPrev)
                lpPrev = lp
                let hp = hpCoeff * (hpPrev + lp - hpIn)
                hpPrev = hp
                hpIn = lp
                let body = hp * bodyEnv * 0.60

                // Layer 3 — Low thump: sine at ~120 Hz, gives the
                // pop physical weight.
                let thumpEnv = min(1.0, t / 0.001) * exp(-t / 0.055)
                let thump = sin(2.0 * .pi * 120.0 * t) * thumpEnv * 0.45

                var sample = crack + body + thump

                // Tail fade to guarantee silence.
                if Double(i) > tailFadeFrames {
                    let tailT = (Double(i) - tailFadeFrames) / (tailFadeSec * sr)
                    sample *= max(0, 1 - tailT)
                }

                ptr[i] = Float(sample * 0.85)
            }
        }
        return buffer
    }

    /// Diatonic major triads of F# major: I (F#), IV (B), V (C#).
    /// Each is root/major-3rd/perfect-5th, fully inside the Ionian
    /// scale — so any voicing drawn from these tones stays major and
    /// in-key.
    private static let majorTriadRoots: [Int] = [0, 5, 7]

    /// Two-note voicings (intervals from root). Inversions + open
    /// spacings so repeated bloom taps don't feel like the same
    /// dyad on loop. All still imply the parent major triad.
    private static let majorTriadVoicings2: [[Int]] = [
        [0, 4],    // root + major 3rd
        [0, 7],    // root + perfect 5th
        [4, 12],   // 3rd + octave (1st inv-flavored)
        [7, 12],   // 5th + octave (2nd inv-flavored)
        [0, 12],   // root + octave doubling
        [0, 16],   // root + 10th (wide)
    ]

    /// Three-note voicings (intervals from root). Mix of root-
    /// position, first- and second-inversion, and open spreads.
    private static let majorTriadVoicings3: [[Int]] = [
        [0, 4, 7],     // root position
        [4, 7, 12],    // 1st inversion
        [7, 12, 16],   // 2nd inversion
        [0, 7, 12],    // root + 5th + octave (no 3rd — bright fifth)
        [0, 7, 16],    // open — root, 5th, wide 10th
        [0, 12, 19],   // root + octave + 5th-above-octave (airy open)
        [0, 4, 12],    // root + 3rd + octave doubling
    ]

    private func randomBloomSemitones() -> [Int] {
        // Voicing probability — a mix of singles and chords. Heavier
        // on chords than the prior pass so consecutive taps produce
        // clear variety. Single voicings walk the full Ionian scale
        // (any degree is fine as a single note); multi-note voicings
        // are drawn from a major triad + inversion template so
        // stacked harmonies are always major but vary in shape.
        let roll = Double.random(in: 0..<1)
        let count = roll < 0.35 ? 1 : (roll < 0.70 ? 2 : 3)

        if count == 1 {
            let degreeIdx: Int
            // Bias toward F# (tonic) so the "randomness" feels like
            // it's orbiting the home note rather than drifting
            // through the scale at random.
            if Double.random(in: 0..<1) < 0.40 {
                degreeIdx = 0
            } else {
                degreeIdx = Int.random(in: 0..<Self.ionianSemitones.count)
            }
            let degree = Self.ionianSemitones[degreeIdx]
            let octaveOffset = Int.random(in: 0..<2) * 12
            return [42 + octaveOffset + degree]
        }

        // Two- or three-note voicing — pick a random root triad and
        // a random voicing template, which together give inversions,
        // doublings, and open spreads so the bloom chord doesn't
        // feel like one fixed stack on loop.
        let root = Self.majorTriadRoots.randomElement() ?? 0
        let voicing: [Int] = count == 3
            ? (Self.majorTriadVoicings3.randomElement() ?? [0, 4, 7])
            : (Self.majorTriadVoicings2.randomElement() ?? [0, 4])
        // One shared octave offset per voicing so the stack stays
        // coherent; the template itself controls internal spread.
        let octaveOffset = Int.random(in: 0..<2) * 12
        var semis = Set<Int>()
        for iv in voicing {
            semis.insert(42 + octaveOffset + root + iv)
        }
        return Array(semis).sorted()
    }

    // ─── Background music loop ──────────────────────────────────────

    /// Starts the background music loop if music is enabled and the
    /// engine is running. Safe to call multiple times — an existing
    /// task is left in place. Idempotent entry points make wiring
    /// onAppear / onChange straightforward for the caller.
    func startMusicIfNeeded() {
        if Self.isUnderTest { return }
        if Self.muted { return }
        if !Self.musicEnabled { return }
        if musicTask != nil { return }
        ensureStarted()
        guard started else { return }
        musicTask = Task { @MainActor [weak self] in
            await self?.runMusicLoop()
            self?.musicTask = nil
        }
    }

    func stopMusic() {
        musicTask?.cancel()
        musicTask = nil
        // Clear the published chord so any pickup/place tones played
        // while the music is off fall back to the color-mapped note
        // instead of pitching against a stale bar.
        currentBassChord = nil
    }

    /// Pickup SFX that latches to the current chord's 3rd. Timbre is
    /// the existing `.pickup` kind. Falls back to the color-mapped
    /// pitch when no music is playing so muted sessions still get an
    /// audible cue.
    func playPickupChordTone(for color: OKLCh) {
        if let chord = currentBassChord {
            playChordTone(chord: chord, chordToneIndex: 1, kind: .pickup,
                          fallbackColor: color, volume: 0.45)
        } else {
            play(color, kind: .pickup)
        }
    }

    /// Place SFX that latches to the current chord's root. Same
    /// fallback semantics as `playPickupChordTone`.
    func playPlaceChordTone(for color: OKLCh) {
        if let chord = currentBassChord {
            playChordTone(chord: chord, chordToneIndex: 0, kind: .place,
                          fallbackColor: color, volume: 0.45)
        } else {
            play(color, kind: .place)
        }
    }

    /// Shared helper — pitches a one-shot at a specific chord tone
    /// (0 = root, 1 = 3rd, 2 = 5th) over the tonic reference octave.
    private func playChordTone(
        chord: MusicChord,
        chordToneIndex: Int,
        kind: Kind,
        fallbackColor: OKLCh,
        volume: Float
    ) {
        if Self.muted || !Self.sfxEnabled { return }
        ensureStarted()
        guard started, engine.isRunning else {
            play(fallbackColor, kind: kind)
            return
        }
        let tonic = 54  // F#3
        let tones = chord.chordDegrees
        let idx = min(max(0, chordToneIndex), tones.count - 1)
        let scaleDeg = tones[idx]
        let semi = tonic + Self.ionianSemitones[scaleDeg]
        let buffer = buffer(for: semi, kind: kind)
        playOneShot(buffer: buffer, volume: volume)
        postNotePlayed(semitone: semi)
    }

    // ─── Background hum ─────────────────────────────────────────────

    /// Start the low looping drone. Safe to call repeatedly; a live
    /// player is left in place. Gated by the master mute and music
    /// toggle for consistency with the other ambient output.
    ///
    /// Defensive: double-checks `engine.isRunning` right before
    /// `play()` and calls `engine.prepare()` to force buffer
    /// pre-roll. `AVAudioPlayerNode.play()` throws an Obj-C
    /// NSException when the engine isn't truly running at the
    /// instant of the call — Swift can't catch those, so the crash
    /// takes the whole app down. The extra guards here are the
    /// closest we can get to "try/catch" without a bridged Obj-C
    /// helper file.
    func startHum() {
        if Self.muted { return }
        if !Self.musicEnabled { return }
        ensureStarted()
        guard started, engine.isRunning else { return }
        if humPlayer != nil { return }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: fanInMixer, format: format)
        let buffer = synthesizeHumBuffer()
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        player.volume = Self.humBaseVolume
        // Force the engine to pre-roll this player before `play()`;
        // avoids the "node not ready" NSException path on device.
        engine.prepare()
        // Last-chance check: if anything raced the engine into a
        // stopped state between ensureStarted() and now (session
        // interruption, route change mid-frame), skip play — it
        // would otherwise throw an Obj-C NSException and terminate.
        guard engine.isRunning else {
            engine.detach(player)
            return
        }
        player.play()
        humPlayer = player
        humBuffer = buffer
    }

    /// Stop the hum and tear its dedicated player off the graph.
    func stopHum() {
        humDecayTask?.cancel()
        humDecayTask = nil
        if let p = humPlayer {
            p.stop()
            p.reset()
            engine.detach(p)
        }
        humPlayer = nil
        humBuffer = nil
    }

    /// Duck the hum's volume up briefly, then decay it back to the
    /// base. Called from the menu whenever a ripple is spawned so
    /// the ambient drone swells slightly with player interaction.
    func boostHum() {
        guard let player = humPlayer else { return }
        humDecayTask?.cancel()
        player.volume = Self.humBoostVolume
        humDecayTask = Task { @MainActor [weak self] in
            // Linear decay from boost to base over ~1.4 s — slow
            // enough that successive ripples stack into a sustained
            // swell rather than popping discrete bumps.
            let steps = 70
            let dropPerStep = (Self.humBoostVolume - Self.humBaseVolume) / Float(steps)
            for _ in 0..<steps {
                try? await Task.sleep(nanoseconds: 20_000_000)
                guard let self, let p = self.humPlayer, !Task.isCancelled else { return }
                let next = max(Self.humBaseVolume, p.volume - dropPerStep)
                p.volume = next
                if next == Self.humBaseVolume { return }
            }
        }
    }

    /// Build the looping hum buffer — 4 beats at ~41 BPM (≈ 5.82 s)
    /// of a low F#1 sine plus a quieter F#2 octave for body, with
    /// short start/end fades so the loop boundary is seamless.
    /// Shared tempo anchor for the melodic loop AND the hum drone —
    /// 0.75× the original 55 BPM feel, now ~41 BPM. Both paths compute
    /// `beatSec = 60.0 / Self.musicBPM` from here so the hum and the
    /// chord progression stay locked to the same pulse.
    static let musicBPM: Double = 55.0 * 0.75

    private func synthesizeHumBuffer() -> AVAudioPCMBuffer {
        let beatSec = 60.0 / Self.musicBPM
        let duration = beatSec * 4
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: frameCount) else {
            fatalError("hum buffer alloc failed")
        }
        buffer.frameLength = frameCount
        let ptr = buffer.floatChannelData![0]
        let twoPi = 2.0 * Double.pi
        let freq = frequency(semitone: 30)   // F#1
        let fadeSec = 0.35
        let fadeFrames = fadeSec * sampleRate
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let f1 =        sin(twoPi * freq * t)
            let f2 = 0.25 * sin(twoPi * freq * 2.0 * t)
            let voice = (f1 + f2) * 0.55
            // Very slow per-beat swell — amplitude rises slightly on
            // each downbeat so the drone feels alive rather than a
            // flat tone.
            let beatPhase = (t / beatSec).truncatingRemainder(dividingBy: 1)
            let swell = 0.82 + 0.18 * sin(beatPhase * twoPi)
            // Fade both ends to zero for a seamless loop boundary.
            let fadeIn = min(1.0, Double(i) / fadeFrames)
            let fadeOut = min(1.0, Double(Int(frameCount) - i) / fadeFrames)
            let fade = fadeIn * fadeOut
            ptr[i] = Float(voice * swell * fade * 0.55)
        }
        return buffer
    }

    // MARK: – Procedural chord progression
    //
    // The music loop now runs against a per-phrase chord progression
    // rather than a flat list of random scale degrees. Each phrase is
    // five chords — `I → X → X → X → I` — where the inner chords are
    // sampled from a functional transition matrix (I→{IV,V,vi,...},
    // V→{I,vi,...}, etc.). Within a single chord's beat, note
    // selection (main note, 1/8 ornament, 16th grace) is weighted
    // toward the chord's root/3rd/5th so the melody outlines the
    // harmony instead of drifting.

    /// Diatonic triads of F# major, tracked by Roman numeral so the
    /// transition table reads like a music-theory cheat sheet.
    private enum MusicChord: CaseIterable {
        case I, ii, iii, IV, V, vi

        /// Root scale-degree within F# Ionian (0 = F#, 1 = G#, …).
        var rootDegree: Int {
            switch self {
            case .I:   return 0
            case .ii:  return 1
            case .iii: return 2
            case .IV:  return 3
            case .V:   return 4
            case .vi:  return 5
            }
        }

        /// Root + 3rd + 5th as scale-degree indices, mod 7.
        var chordDegrees: [Int] {
            let r = rootDegree
            return [r, (r + 2) % 7, (r + 4) % 7]
        }
    }

    /// Functional transition weights. Each entry maps the current
    /// chord to the set of chords that can follow and the relative
    /// probability of each. Values are not normalized — the sampler
    /// just picks proportionally. Tuned to feel cadential: V pulls
    /// hardest to I, ii pulls toward V, etc.
    private static let chordTransitions: [MusicChord: [(MusicChord, Double)]] = [
        .I:   [(.IV, 0.32), (.V, 0.28), (.vi, 0.22), (.ii, 0.10), (.iii, 0.08)],
        .ii:  [(.V,  0.55), (.IV, 0.20), (.I,  0.15), (.vi, 0.10)],
        .iii: [(.vi, 0.38), (.IV, 0.30), (.I,  0.22), (.ii, 0.10)],
        .IV:  [(.I,  0.38), (.V,  0.32), (.vi, 0.18), (.ii, 0.12)],
        .V:   [(.I,  0.62), (.vi, 0.22), (.IV, 0.10), (.ii, 0.06)],
        .vi:  [(.IV, 0.34), (.V,  0.28), (.ii, 0.18), (.I,  0.14), (.iii, 0.06)]
    ]

    private static func nextChord(from current: MusicChord) -> MusicChord {
        let options = chordTransitions[current] ?? [(.I, 1.0)]
        let total = options.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total)
        for (chord, weight) in options {
            roll -= weight
            if roll <= 0 { return chord }
        }
        return .I
    }

    /// 4-chord phrase: tonic → two weighted steps → cadence chord.
    /// The loop repeats, so the next iteration's leading I provides
    /// the resolution — I doesn't get emitted twice in a row at the
    /// phrase boundary. Cadence chord skews toward V/IV/ii so the
    /// following I lands as a genuine resolution.
    private static func buildChordPhrase() -> [MusicChord] {
        var phrase: [MusicChord] = [.I]
        var current: MusicChord = .I
        for _ in 0..<2 {
            current = nextChord(from: current)
            phrase.append(current)
        }
        let cadenceOptions: [MusicChord] = [.V, .V, .V, .IV, .IV, .ii]
        phrase.append(cadenceOptions.randomElement() ?? .V)
        return phrase
    }

    /// Pick a scale-degree index weighted toward the current chord's
    /// tones. `chordWeight` is the probability of landing on a chord
    /// tone (root/3rd/5th); the remaining mass falls to any scale
    /// degree. Higher chord-weights make arpeggiated/outlining
    /// melodies; lower weights give more scalar motion.
    private static func pickDegree(for chord: MusicChord,
                                    chordWeight: Double) -> Int {
        if Double.random(in: 0..<1) < chordWeight {
            return chord.chordDegrees.randomElement() ?? chord.rootDegree
        }
        return Int.random(in: 0..<ionianSemitones.count)
    }

    /// Phrase: `I → X → X → X → I` — 5-chord progression over a 4/4
    /// groove at ~55 BPM. Within each chord: 25% skip (rest), 25%
    /// 8th-note ornament between
    /// this note and the next. Top octave is excluded so the
    /// melody stays in F#3..B3 range — companion rule to the
    /// single-note octave cap.
    private func runMusicLoop() async {
        let beatSec = 60.0 / Self.musicBPM
        // Each chord occupies one full beat. The bass note at the
        // downbeat holds the beat; melody + ornament + grace all
        // play at half-length so two melody passes fit inside each
        // chord's beat — the listener hears the bass at tempo plus a
        // chord-outlining melodic flurry on top.
        let beatNs: UInt64 = UInt64(beatSec * 1_000_000_000)
        let subBeatNs: UInt64 = beatNs / 2          // half-beat = melody pass
        let quarterSubNs: UInt64 = subBeatNs / 4    // 16th of the sub-beat
        let timbres: [Kind] = [.bloom, .choir, .glassHarmonica]
        while !Task.isCancelled && Self.musicEnabled && !Self.muted {
            let tonic = 54  // F#3
            let phrase = Self.buildChordPhrase()

            for (i, chord) in phrase.enumerated() {
                if Task.isCancelled || !Self.musicEnabled || Self.muted { return }

                // Publish the chord so pickup/place SFX called during
                // this beat can latch to its root/3rd.
                currentBassChord = chord

                // Bass note — root of the current chord, one octave
                // below the melody range. Only one per chord; holds
                // its full length regardless of what the melody does.
                let bassSemi = tonic + Self.ionianSemitones[chord.rootDegree] - 12
                playBassNote(semi: bassSemi, volume: 0.34)

                // Two melody sub-beats per chord — half-length each.
                for subBeat in 0..<2 {
                    if Task.isCancelled || !Self.musicEnabled || Self.muted { return }
                    let mainDeg = Self.pickDegree(for: chord, chordWeight: 0.80)
                    let semi = tonic + Self.ionianSemitones[mainDeg]
                    let roll = Double.random(in: 0..<1)
                    let canSkip = !(i == 0 && subBeat == 0)
                        && !(i == phrase.count - 1 && subBeat == 1)
                    // Lower skip rate than the old loop — dropping
                    // events blurs the chord progression. 15% keeps
                    // breath in without making harmony inaudible.
                    if canSkip && roll < 0.15 {
                        try? await Task.sleep(nanoseconds: subBeatNs)
                        continue
                    }
                    let ornament = roll >= 0.75

                    // Main note at the sub-beat downbeat.
                    playBeatNote(semi: semi, degIdx: mainDeg, tonic: tonic,
                                 kind: timbres.randomElement() ?? .bloom,
                                 volume: 0.24, chord: chord)

                    try? await Task.sleep(nanoseconds: quarterSubNs)
                    if Task.isCancelled || !Self.musicEnabled || Self.muted { return }
                    maybePlaySixteenthGrace(tonic: tonic, timbres: timbres, chord: chord)

                    try? await Task.sleep(nanoseconds: quarterSubNs)
                    if Task.isCancelled || !Self.musicEnabled || Self.muted { return }
                    if ornament {
                        let ornDeg = Self.pickDegree(for: chord, chordWeight: 0.60)
                        let ornSemi = tonic + Self.ionianSemitones[ornDeg]
                        playBeatNote(semi: ornSemi, degIdx: ornDeg, tonic: tonic,
                                     kind: timbres.randomElement() ?? .bloom,
                                     volume: 0.20, chord: chord)
                    }

                    try? await Task.sleep(nanoseconds: quarterSubNs)
                    if Task.isCancelled || !Self.musicEnabled || Self.muted { return }
                    maybePlaySixteenthGrace(tonic: tonic, timbres: timbres, chord: chord)

                    try? await Task.sleep(nanoseconds: quarterSubNs)
                }
            }
        }
    }

    /// Chord-root bass, one octave under the melody. Always a pad
    /// timbre so the low end blends rather than barking, and a touch
    /// louder than melody notes since it anchors the progression.
    private func playBassNote(semi: Int, volume: Float) {
        let buffer = self.buffer(for: semi, kind: .bloom)
        playOneShot(buffer: buffer, volume: volume)
        postNotePlayed(semitone: semi)
    }

    /// Play a note at a sub-beat position. Non-tonic notes get a 1/4
    /// chance to stack a chord tone above the main note. Tonic (F#)
    /// notes ALWAYS get extra body — either the full F# triad (F# +
    /// A# + C#, 50%) or a pair of F#'s one octave above and below
    /// the main (50%). Either way the tonic lands as a chord event
    /// so the following 16th grace slot respects the breath rule.
    private func playBeatNote(semi: Int, degIdx: Int, tonic: Int,
                               kind: Kind, volume: Float,
                               chord: MusicChord) {
        let buffer = self.buffer(for: semi, kind: kind)
        playOneShot(buffer: buffer, volume: volume)
        postNotePlayed(semitone: semi)

        let mainMod = ((degIdx % 7) + 7) % 7

        // F# tonic emphasis — always stack something on the tonic so
        // it lands with weight, not as a single thin voice.
        if mainMod == 0 {
            if Double.random(in: 0..<1) < 0.5 {
                // Full F# triad: main F# + A# (3rd) + C# (5th).
                let thirdSemi = tonic + Self.ionianSemitones[2]
                let fifthSemi = tonic + Self.ionianSemitones[4]
                playOneShot(buffer: self.buffer(for: thirdSemi, kind: kind),
                            volume: volume * 0.65)
                playOneShot(buffer: self.buffer(for: fifthSemi, kind: kind),
                            volume: volume * 0.65)
                postNotePlayed(semitone: thirdSemi)
                postNotePlayed(semitone: fifthSemi)
            } else {
                // Octave pair — F# one octave above and one below
                // the main note. Quieter so the octaves reinforce
                // the tonic without overshadowing it.
                let octaveUp = semi + 12
                let octaveDown = semi - 12
                playOneShot(buffer: self.buffer(for: octaveUp, kind: kind),
                            volume: volume * 0.55)
                playOneShot(buffer: self.buffer(for: octaveDown, kind: kind),
                            volume: volume * 0.55)
                postNotePlayed(semitone: octaveUp)
                postNotePlayed(semitone: octaveDown)
            }
            lastBeatWasChord = true
            return
        }

        guard Double.random(in: 0..<1) < 0.25 else {
            lastBeatWasChord = false
            return
        }
        // Pick a chord tone that isn't the main note — guarantees an
        // actual interval rather than a doubled unison.
        let candidates = chord.chordDegrees.filter { $0 != mainMod }
        guard let harmonyMod = candidates.randomElement() else {
            lastBeatWasChord = false
            return
        }
        // Force the harmony to sit above the melody note by rotating
        // upward until we clear it, then tracking any octave jump so
        // the pitch comes out right.
        var steps = harmonyMod - mainMod
        if steps <= 0 { steps += 7 }
        let degreeCount = Self.ionianSemitones.count
        let targetDeg = mainMod + steps
        let wrappedDeg = targetDeg % degreeCount
        let octaveJump = (targetDeg / degreeCount) * 12
        let harmonySemi = tonic + Self.ionianSemitones[wrappedDeg] + octaveJump
        let harmonyBuffer = self.buffer(for: harmonySemi, kind: kind)
        playOneShot(buffer: harmonyBuffer, volume: volume * 0.70)
        postNotePlayed(semitone: harmonySemi)
        lastBeatWasChord = true
    }

    /// 1/16 chance to play a grace note at a 16th-note off-eighth
    /// position. Called twice per beat — at 1/4 and 3/4 — never at
    /// 1/2 (which belongs to the 1/8-note ornament grid). Degree is
    /// weighted toward the current chord's tones so the decoration
    /// reinforces the harmony. Skips (and clears the flag) when the
    /// previous beat event was a chord so harmonies don't get
    /// stepped on the moment they start sounding.
    ///
    /// On a fire, schedules a chained grace — 1/4 chance to play
    /// another 16th note half a 16th later, with each chained note
    /// stepping ±1 or 0 scale degrees from the previous note,
    /// repeating until the chain breaks.
    private func maybePlaySixteenthGrace(tonic: Int,
                                          timbres: [Kind],
                                          chord: MusicChord) {
        if lastBeatWasChord {
            lastBeatWasChord = false
            return
        }
        guard Double.random(in: 0..<1) < (1.0 / 16.0) else { return }
        let firstIndex = playSixteenthGrace(
            tonic: tonic, timbres: timbres, chord: chord, previousIndex: nil
        )
        scheduleSixteenthChain(
            tonic: tonic, timbres: timbres, chord: chord,
            startingFromIndex: firstIndex
        )
    }

    /// Single-shot grace render. Returns the scale-position index
    /// that was played so the chain can continue stepping relative
    /// to it. `previousIndex` nil = chord-weighted random pick (the
    /// initial fire); non-nil = step the previous index by -1, 0, or
    /// +1 scale degrees so chained notes feel like a passing line.
    /// The index is unbounded — octaves wrap via floored division so
    /// chains can climb or descend through the scale freely.
    @discardableResult
    private func playSixteenthGrace(tonic: Int,
                                     timbres: [Kind],
                                     chord: MusicChord,
                                     previousIndex: Int?) -> Int {
        let degreeCount = Self.ionianSemitones.count
        let scaleIndex: Int
        if let prev = previousIndex {
            scaleIndex = prev + Int.random(in: -1...1)
        } else {
            scaleIndex = Self.pickDegree(for: chord, chordWeight: 0.55)
        }
        let octaveOffset = Int((Double(scaleIndex) / Double(degreeCount)).rounded(.down))
        let modIndex = scaleIndex - octaveOffset * degreeCount
        let semi = tonic + Self.ionianSemitones[modIndex] + octaveOffset * 12
        let kind = timbres.randomElement() ?? .bloom
        let buffer = self.buffer(for: semi, kind: kind)
        // Quieter than main/ornament so grace notes sit under the
        // melodic line, not on top of it.
        playOneShot(buffer: buffer, volume: 0.18)
        postNotePlayed(semitone: semi)
        return scaleIndex
    }

    /// Detached chain runner — each step waits half a 16th-note,
    /// then 1/4 chance to fire another grace and continue. The
    /// chained note steps ±1 or 0 scale degrees from the previous
    /// fired note. Runs off the main loop so the beat grid stays on
    /// time.
    private func scheduleSixteenthChain(tonic: Int,
                                         timbres: [Kind],
                                         chord: MusicChord,
                                         startingFromIndex initial: Int) {
        // Half the prior 16th-note step — was beatNs/8, now beatNs/16
        // so chains burst as a flourish rather than crawl.
        let beatSec = 60.0 / Self.musicBPM
        let stepNs = UInt64(beatSec * 1_000_000_000) / 16
        Task { [weak self] in
            var lastIndex = initial
            while true {
                try? await Task.sleep(nanoseconds: stepNs)
                guard let self,
                      Self.musicEnabled,
                      !Self.muted,
                      Double.random(in: 0..<1) < 0.25
                else { return }
                lastIndex = self.playSixteenthGrace(
                    tonic: tonic, timbres: timbres, chord: chord,
                    previousIndex: lastIndex
                )
            }
        }
    }

    /// Post a note-played event so UI that reacts to audio (e.g. the
    /// continuous-grid menu backdrop's flare spawning) can pick it
    /// up. Marshals to the main queue since observers are typically
    /// SwiftUI views and NotificationCenter delivers on the posting
    /// queue.
    private func postNotePlayed(semitone: Int) {
        NotificationCenter.default.post(
            name: .kromaNotePlayed,
            object: nil,
            userInfo: ["semitone": semitone]
        )
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
        // Top octave stripped — single-note playback now covers only
        // F#2..B3 (span of 1 octave from base). Chord voicings (solve
        // chord + bloom) build their own semitones elsewhere so they
        // still reach higher notes; this cap is for single notes only.
        case .pickup, .place: baseMidi = 42; octaveSpan = 1
        case .bloom, .choir, .glassHarmonica:
            baseMidi = 42; octaveSpan = 1
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
        if let cached = cache[key] {
            // Promote to most-recently-used.
            if let idx = cacheOrder.firstIndex(of: key) {
                cacheOrder.append(cacheOrder.remove(at: idx))
            }
            return cached
        }
        let freq = frequency(semitone: semitone)
        let buffer: AVAudioPCMBuffer
        switch kind {
        case .pickup, .place: buffer = synthesizeSoftMallet(frequency: freq)
        case .bloom:          buffer = synthesizePadBloom(frequency: freq)
        case .choir:          buffer = synthesizeChoir(frequency: freq)
        case .glassHarmonica: buffer = synthesizeGlassHarmonica(frequency: freq)
        }
        // Evict least-recently-used if at capacity.
        if cache.count >= cacheCapacity, let evict = cacheOrder.first {
            cache.removeValue(forKey: evict)
            cacheOrder.removeFirst()
        }
        cache[key] = buffer
        cacheOrder.append(key)
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
        applyRelease(ptr, frameCount: Int(frameCount))
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
        applyRelease(ptr, frameCount: Int(frameCount))
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
        applyRelease(ptr, frameCount: Int(frameCount))
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
        applyRelease(ptr, frameCount: Int(frameCount))
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
        applyRelease(ptr, frameCount: Int(frameCount))
        return buffer
    }

    /// Linear fade to zero across the last `releaseSec` seconds of
    /// the buffer. Every synthesis path finishes mid-decay with a
    /// non-zero tail amplitude — without this ramp, playback ends at
    /// a hard amplitude step that the speaker reproduces as a click.
    private func applyRelease(_ ptr: UnsafeMutablePointer<Float>,
                              frameCount: Int,
                              releaseSec: Double = 0.08) {
        let releaseFrames = min(frameCount, Int(releaseSec * sampleRate))
        guard releaseFrames > 1 else { return }
        let start = frameCount - releaseFrames
        for i in start..<frameCount {
            let t = Float(i - start) / Float(releaseFrames - 1)
            ptr[i] *= (1.0 - t)
        }
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
        if Self.isUnderTest { return }
        // `started` can linger true after iOS tears down the graph
        // (interruption, route change). Trust engine.isRunning as the
        // source of truth; fall through to restart when the flag lies.
        if started && engine.isRunning { return }
        started = false
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

    /// Called by the app when returning to the foreground. Rebuilds the
    /// engine if iOS paused it and restarts the music loop.
    func appDidBecomeActive() {
        ensureStarted()
        if Self.musicEnabled { startMusicIfNeeded() }
    }

    /// Called by the app when entering the background. Stops the music
    /// loop and pauses the engine so that when the app returns, the
    /// engine is cleanly stopped — not in an ambiguous partially-torn-
    /// down state that can crash on the next play() call. The
    /// AVAudioSession interruptionNotification doesn't reliably fire for
    /// plain app-switches on newer iOS versions, so this provides a
    /// deterministic teardown path.
    func appDidEnterBackground() {
        stopMusic()
        for p in playerPool where p.isPlaying { p.stop() }
        if engine.isRunning {
            engine.pause()
        }
        started = false
    }

    private func handleInterruption(_ notif: Notification) {
        guard let info = notif.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            stopMusic()
            for p in playerPool where p.isPlaying { p.stop() }
            started = false
        case .ended:
            if let optsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let opts = AVAudioSession.InterruptionOptions(rawValue: optsRaw)
                if opts.contains(.shouldResume) {
                    ensureStarted()
                    if Self.musicEnabled { startMusicIfNeeded() }
                }
            }
        @unknown default:
            break
        }
    }

    private func handleConfigurationChange() {
        for p in playerPool where p.isPlaying { p.stop() }
        started = false
        ensureStarted()
        if Self.musicEnabled { startMusicIfNeeded() }
    }

    private func playOneShot(buffer: AVAudioPCMBuffer, volume: Float) {
        guard started, engine.isRunning else { return }
        let player = playerPool[nextPlayerIdx]
        nextPlayerIdx = (nextPlayerIdx + 1) % poolSize
        if player.isPlaying { player.stop() }
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        guard engine.isRunning else { return }
        player.play()
    }

    /// Plays a buffer on the shared tempo grid — defers the one-shot
    /// by however long it takes to reach the next grid tick, so all
    /// grid-snapped playbacks interlock. Pure play-immediately path
    /// kicks in when the press already falls within ~5ms of a tick.
    private func playOnGrid(buffer: AVAudioPCMBuffer, volume: Float) {
        guard started, engine.isRunning, let anchor = tempoAnchor else { return }
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
            guard let self, self.started, self.engine.isRunning else { return }
            if player.isPlaying { player.stop() }
            player.volume = volume
            player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in }
            guard self.engine.isRunning else { return }
            player.play()
        }
    }

    private func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
        min(max(v, lo), hi)
    }
}
