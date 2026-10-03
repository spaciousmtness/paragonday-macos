import Foundation

/// A soft struck bell, synthesised so the app ships no audio files.
///
/// A nod to Brenda Hutchinson's dailybell, which rings bells at sunrise and sunset: Light Glass rings
/// one when a block of light has run through.
///
/// The partials follow a minor-third church bell (hum, prime, tierce, quint, nominal and a few upper
/// partials), each with its own decay, a soft-mallet attack, and a slight detune on the low partials
/// so it beats gently instead of buzzing. Output is a mono 16-bit WAV that NSSound can play directly.
enum LightGlassBell {

    /// (ratio to the prime, amplitude, decay time constant in seconds)
    static let partials: [(Double, Double, Double)] = [
        (0.5, 0.30, 2.8),    // hum
        (1.0, 0.45, 2.2),    // prime
        (1.19, 0.30, 1.9),   // tierce (the minor third that makes it sound like a bell)
        (1.5, 0.12, 1.4),    // quint
        (2.0, 0.32, 1.5),    // nominal
        (2.51, 0.10, 0.9),
        (2.66, 0.08, 0.8),
        (3.01, 0.06, 0.6),
        (4.07, 0.035, 0.35),
    ]

    static func samples(prime: Double = 392.0, seconds: Double = 6.0, sampleRate: Double = 44_100,
                        peak: Double = 0.55) -> [Double] {
        let n = Int(seconds * sampleRate)
        var out = [Double](repeating: 0, count: n)
        let attack = 0.006 * sampleRate
        for (ratio, amp, decay) in partials {
            let f = prime * ratio
            // Low partials get a twin a fraction of a hertz away: the slow beat of a real bell.
            let twin = ratio <= 1.0 ? 0.6 : 0
            for i in 0..<n {
                let t = Double(i) / sampleRate
                let env = exp(-t / decay)
                var s = sin(2 * .pi * f * t)
                if twin > 0 { s = 0.6 * s + 0.4 * sin(2 * .pi * (f + twin) * t) }
                out[i] += amp * env * s
            }
        }
        // Raised-cosine attack (a felt mallet, no click), and a short fade so the tail ends at silence.
        let fade = Int(0.6 * sampleRate)
        for i in 0..<n {
            if Double(i) < attack { out[i] *= 0.5 - 0.5 * cos(.pi * Double(i) / attack) }
            if i >= n - fade { out[i] *= Double(n - i) / Double(fade) }
        }
        let maxAbs = out.map { abs($0) }.max() ?? 1
        let scale = maxAbs > 0 ? peak / maxAbs : 0
        return out.map { $0 * scale }
    }

    /// The bell as WAV bytes (RIFF, PCM, mono, 16-bit).
    static func wav(prime: Double = 392.0, seconds: Double = 6.0, sampleRate: Int = 44_100) -> Data {
        let pcm = samples(prime: prime, seconds: seconds, sampleRate: Double(sampleRate))
        var data = Data()
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(pcm.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); put32(36 + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put32(16)
        put16(1); put16(1)                                   // PCM, mono
        put32(UInt32(sampleRate)); put32(UInt32(sampleRate * 2))
        put16(2); put16(16)                                  // block align, bits per sample
        data.append(contentsOf: Array("data".utf8)); put32(bytes)
        for s in pcm {
            let v = Int16(max(-1, min(1, s)) * Double(Int16.max))
            put16(UInt16(bitPattern: v))
        }
        return data
    }
}
