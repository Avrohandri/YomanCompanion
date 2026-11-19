// Synthesizes the cat's sounds (no recorded audio needed): a "meow" and a short "mrrp" trill.
//
//   swift tools/make_sounds.swift Assets/sounds

import Foundation

let rate = 44_100.0

/// Harmonic synthesis with moving formants: pitch contour + vowel glide (m-i-a-o-w).
func voice(duration: Double, pitch: (Double) -> Double, f1: (Double) -> Double, f2: (Double) -> Double,
           envelope: (Double) -> Double, trill: Double = 0) -> [Double] {
    let n = Int(duration * rate)
    var phase = 0.0
    var out = [Double](repeating: 0, count: n)
    for i in 0..<n {
        let t = Double(i) / rate, u = t / duration
        let vib = 1 + 0.015 * sin(2 * .pi * 6 * t)
        let f0 = pitch(u) * vib
        phase += 2 * .pi * f0 / rate
        var s = 0.0
        for k in 1...12 {
            let f = f0 * Double(k)
            if f > 9000 { break }
            let a1 = exp(-pow((f - f1(u)) / 180, 2)), a2 = 0.6 * exp(-pow((f - f2(u)) / 300, 2))
            s += (a1 + a2 + 0.04 / Double(k)) * sin(phase * Double(k))
        }
        let am = trill > 0 ? 0.55 + 0.45 * sin(2 * .pi * trill * t) : 1
        out[i] = s * envelope(u) * am
    }
    let peak = out.map(abs).max() ?? 1
    return out.map { $0 / peak * 0.5 }
}

func lerp(_ pts: [(Double, Double)]) -> (Double) -> Double {
    { u in
        guard let j = pts.firstIndex(where: { $0.0 >= u }), j > 0 else { return u <= 0 ? pts[0].1 : pts.last!.1 }
        let (a, b) = (pts[j - 1], pts[j])
        let t = (u - a.0) / (b.0 - a.0)
        let s = t * t * (3 - 2 * t)
        return a.1 + (b.1 - a.1) * s
    }
}

func writeWAV(_ samples: [Double], to url: URL) throws {
    var d = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    let bytes = UInt32(samples.count * 2)
    d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
    d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
    d.append(contentsOf: Array("data".utf8)); u32(bytes)
    for s in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, s)) * 32_000))) }
    try d.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets/sounds")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let meow = voice(
    duration: 0.62,
    pitch: lerp([(0, 560), (0.3, 820), (0.65, 700), (1, 470)]),
    f1: lerp([(0, 350), (0.25, 650), (0.5, 950), (0.8, 600), (1, 450)]),
    f2: lerp([(0, 1900), (0.25, 2300), (0.5, 1500), (0.8, 1000), (1, 850)]),
    envelope: lerp([(0, 0), (0.06, 0.35), (0.18, 1), (0.75, 0.85), (1, 0)]))
try writeWAV(meow, to: out.appendingPathComponent("meow.wav"))

let mrrp = voice(
    duration: 0.32,
    pitch: lerp([(0, 480), (0.5, 640), (1, 720)]),
    f1: lerp([(0, 400), (1, 700)]),
    f2: lerp([(0, 1600), (1, 2000)]),
    envelope: lerp([(0, 0), (0.12, 1), (0.8, 0.8), (1, 0)]),
    trill: 28)
try writeWAV(mrrp, to: out.appendingPathComponent("mrrp.wav"))
print("Wrote meow.wav and mrrp.wav to \(out.path)")
