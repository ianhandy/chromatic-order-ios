//  Central catalog of music-generation rules. All tempo, probability,
//  harmony, scale, and volume knobs used by GlassyAudio live here so
//  editing the game's musical feel is a single-file change.
//
//  New rules / parameters should be added here as they're introduced,
//  and GlassyAudio should reference the named constants instead of
//  hardcoding numerics. Values are plain Swift — no import of the
//  audio engine — so the rules file is trivially importable from
//  tests or analysis tools.

import Foundation

enum MusicRules {

    // MARK: – Tempo / time grid

    enum Tempo {
        /// Beats per minute for the menu + background music loop.
        static let bpm: Double = 55
        /// Derived: seconds per beat at the configured BPM.
        static let beatSec: Double = 60.0 / bpm
        /// Derived: seconds per 8th-note (half of a beat).
        static let eighthSec: Double = beatSec / 2
        /// Derived: seconds per 16th-note (quarter of a beat).
        static let sixteenthSec: Double = beatSec / 4
    }

    // MARK: – Probabilities

    enum Probability {
        /// Chance a given beat in the melodic phrase skips entirely
        /// (rests for the full beat). Bookending tonics are exempt.
        static let skipBeat: Double = 0.25
        /// Chance a given beat adds an 8th-note ornament at the 1/2
        /// position — a neighboring scale degree played half a beat
        /// after the downbeat.
        static let ornamentEighth: Double = 0.25
        /// Chance of a 16th-note grace note firing at each
        /// off-eighth position (1/4 and 3/4 of the beat). 1/16.
        static let sixteenthGrace: Double = 1.0 / 16.0
        /// Chance that any main or 8th-note ornament spawns a
        /// simultaneous harmony (third or fifth above).
        static let harmony: Double = 1.0 / 8.0
        /// Chance the per-tap color note jitters up or down an
        /// octave instead of landing in the hue-bucket default.
        static let octaveJitter: Double = 0.30
    }

    // MARK: – Harmony intervals

    enum Harmony {
        /// Scale-degree offset counted as a third interval in the
        /// tonic's Ionian scale (F# → A#).
        static let thirdOffsetDegrees: Int = 2
        /// Scale-degree offset counted as a fifth (F# → C#).
        static let fifthOffsetDegrees: Int = 4
        /// Volume multiplier on the harmony voice relative to its
        /// main note. Keeps the melody line on top.
        static let volumeMultiplier: Double = 0.70
    }

    // MARK: – Scale / key

    enum Scale {
        /// F# Ionian — seven scale degrees as semitone offsets from
        /// the tonic. Drives color→note mapping, chord voicings,
        /// phrase construction, and the anti-repeat nudge.
        static let ionianSemitones: [Int] = [0, 2, 4, 5, 7, 9, 11]
        /// MIDI semitone for the music-loop tonic: F#3.
        static let tonicMidi: Int = 54
        /// Usable semitone range for single-note playback (pickup /
        /// place / music loop). The old top octave was cut to keep
        /// notes in a calmer register.
        static let singleNoteLow: Int = 30   // F#1
        static let singleNoteHigh: Int = 78  // F#5
    }

    // MARK: – Volumes

    enum Volume {
        /// Main downbeat note in the music loop.
        static let main: Float = 0.26
        /// 8th-note ornament between beats.
        static let ornamentEighth: Float = 0.22
        /// 16th-note grace at off-eighth positions.
        static let sixteenthGrace: Float = 0.18
        /// Solved-puzzle chord — full F# major triad.
        static let solveChord: Float = 0.82
        /// Ambient background hum base level.
        static let humBase: Float = 0.06
        /// Ambient background hum when ducked up by a menu ripple.
        static let humBoost: Float = 0.22
    }

    // MARK: – Chord voicings

    enum Chord {
        /// Solve-chord per-voice octave options. Each play picks one
        /// option per voice, so the chord identity stays fixed
        /// (F# major, root/root/3rd/5th/root) while the sonic color
        /// rotates across solves.
        static let solveRootLow: [Int]  = [42, 54]   // F#2 / F#3
        static let solveRootMid: [Int]  = [54, 66]   // F#3 / F#4
        static let solveThird:   [Int]  = [46, 58]   // A#2 / A#3
        static let solveFifth:   [Int]  = [49, 61]   // C#3 / C#4
        static let solveTop:     [Int]  = [66, 78]   // F#4 / F#5

        /// Major triad root offsets (F# major I / IV / V). All three
        /// are built entirely from in-scale tones.
        static let majorTriadRoots: [Int] = [0, 5, 7]
        /// Two-note voicings (intervals from root) used by bloom.
        static let majorTriadTwoNote: [[Int]] = [
            [0, 4], [0, 7], [4, 12], [7, 12], [0, 12], [0, 16]
        ]
        /// Three-note voicings (intervals from root) used by bloom.
        static let majorTriadThreeNote: [[Int]] = [
            [0, 4, 7], [4, 7, 12], [7, 12, 16],
            [0, 7, 12], [0, 7, 16], [0, 12, 19], [0, 4, 12]
        ]
    }

    // MARK: – Envelopes

    enum Envelope {
        /// Release window applied to the tail of every synthesized
        /// one-shot buffer so playback ends at zero amplitude
        /// (prevents the click that otherwise fires when a buffer
        /// stops mid-decay).
        static let releaseSec: Double = 0.08
        /// Attack ramps for each timbre.
        static let malletAttackSec: Double   = 0.010
        static let bloomAttackSec: Double    = 0.090
        static let choirAttackSec: Double    = 0.120
        static let glassAttackSec: Double    = 0.180
    }
}
