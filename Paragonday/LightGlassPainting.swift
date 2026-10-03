import AppKit
import SwiftUI

// Melting Glass: the Light Glass hourglass painted after Dalí, ported from the board's web sketch
// (sketches/timer-dali.html). The glass hangs by a soft watch from a dead tree's branch over a pale
// plain; its foot slumps over a stone ledge, propped by a crutch, and drips light. It is crisp at
// sunrise and slumps as the light runs out, then sets again through the night. Every line is a seeded
// wobble, so the drawing is the same on every render and never clean.
//
// Scene units are the sketch's: 400 wide, 580 tall from y 10. Lines and shapes are drawn in those
// units and scaled; words are set at fixed point sizes so they stay legible in a 300-point popover.

// MARK: - The hand

enum Hand {
    /// mulberry32, as the sketch's `rand(seed)`: the same seed draws the same wobble.
    static func rand(_ seed: Int) -> () -> Double {
        var a = UInt32(truncatingIfNeeded: seed)
        return {
            a = a &+ 0x6D2B79F5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296
        }
    }

    /// Pushes a polyline sideways by smooth noise: a slow sway of the wrist plus a small tremor.
    static func wobble(_ pts: [CGPoint], _ amp: Double, _ seed: Int, _ wl: Double = 24) -> [CGPoint] {
        let n = pts.count
        if n < 2 || amp == 0 { return pts }
        let R = rand(seed)
        var L = [0.0]
        for i in 1..<n { L.append(L[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
        let K = Int(ceil(L[n - 1] / wl)) + 3
        var k1: [Double] = [], k2: [Double] = []
        for _ in 0..<K { k1.append(R() * 2 - 1) }
        for _ in 0..<(K * 4 + 4) { k2.append(R() * 2 - 1) }
        func ip(_ A: [Double], _ s: Double) -> Double {
            let k = Int(floor(s)), fr = s - Double(k)
            let a = k >= 0 && k < A.count ? A[k] : 0
            let b = k + 1 >= 0 && k + 1 < A.count ? A[k + 1] : a
            return a + (b - a) * (1 - cos(fr * .pi)) / 2
        }
        return pts.indices.map { i in
            let q0 = pts[max(0, i - 1)], q1 = pts[min(n - 1, i + 1)]
            var nx = q0.y - q1.y, ny = q1.x - q0.x
            let l = hypot(nx, ny) == 0 ? 1 : hypot(nx, ny)
            nx /= l; ny /= l
            let v = amp * (ip(k1, L[i] / wl) + 0.3 * ip(k2, L[i] / (wl / 4)))
            return CGPoint(x: pts[i].x + nx * v, y: pts[i].y + ny * v)
        }
    }

    /// A smooth path through points (Catmull-Rom as cubic Béziers).
    static func curve(_ p: [CGPoint], closed: Bool = false, into path: inout Path) {
        let n = p.count
        guard n >= 2 else { return }
        path.move(to: p[0])
        let m = closed ? n : n - 1
        for i in 0..<m {
            let p0 = p[closed ? (i - 1 + n) % n : max(0, i - 1)], p1 = p[i], p2 = p[(i + 1) % n]
            let p3 = p[closed ? (i + 2) % n : min(n - 1, i + 2)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        if closed { path.closeSubpath() }
    }

    static func curve(_ p: [CGPoint], closed: Bool = false) -> Path {
        var path = Path()
        curve(p, closed: closed, into: &path)
        return path
    }

    /// Resamples coarse points into dense ones, so the wobble has somewhere to live.
    static func dense(_ pts: [CGPoint], _ step: Double = 4, closed: Bool = false) -> [CGPoint] {
        var out: [CGPoint] = []
        let P = closed ? pts + [pts[0]] : pts
        for i in 0..<(P.count - 1) {
            let a = P[i], b = P[i + 1]
            let n = max(1, Int((hypot(b.x - a.x, b.y - a.y) / step).rounded()))
            for k in 0..<n {
                let t = Double(k) / Double(n)
                out.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        if !closed { out.append(P[P.count - 1]) }
        return out
    }

    /// A smooth curve through a few knots, sampled densely.
    static func spline(_ pts: [CGPoint], _ step: Double = 4, closed: Bool = false) -> [CGPoint] {
        let n = pts.count
        var out: [CGPoint] = []
        let m = closed ? n : n - 1
        for i in 0..<m {
            let p0 = pts[closed ? (i - 1 + n) % n : max(0, i - 1)], p1 = pts[i], p2 = pts[(i + 1) % n]
            let p3 = pts[closed ? (i + 2) % n : min(n - 1, i + 2)]
            let k = max(2, Int((hypot(p2.x - p1.x, p2.y - p1.y) / step).rounded()))
            for j in 0..<k {
                let t = Double(j) / Double(k), t2 = t * t, t3 = t2 * t
                func c(_ a: CGFloat, _ b: CGFloat, _ cc: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * ((2 * b) + (-a + cc) * t + (2 * a - 5 * b + 4 * cc - d) * t2 + (-a + 3 * b - 3 * cc + d) * t3)
                }
                out.append(CGPoint(x: c(p0.x, p1.x, p2.x, p3.x), y: c(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        if !closed { out.append(pts[n - 1]) }
        return out
    }

    /// Runs a line on past its ends a little, as a pen does.
    static func extend(_ pts: [CGPoint], _ a: Double, _ b: Double) -> [CGPoint] {
        let n = pts.count
        guard n >= 2 else { return pts }
        let s = pts[0], s1 = pts[1], e = pts[n - 1], e1 = pts[n - 2]
        let ds = max(1e-9, hypot(s.x - s1.x, s.y - s1.y)), de = max(1e-9, hypot(e.x - e1.x, e.y - e1.y))
        return [CGPoint(x: s.x + (s.x - s1.x) / ds * a, y: s.y + (s.y - s1.y) / ds * a)] + pts +
            [CGPoint(x: e.x + (e.x - e1.x) / de * b, y: e.y + (e.y - e1.y) / de * b)]
    }

    /// A hand-drawn circle: slightly egg-shaped, spiralling out, the pen overshooting where it started.
    static func ringPts(_ cx: Double, _ cy: Double, _ r: Double, _ seed: Int, over: Double = 0.16,
                        amp: Double = 0.06) -> [CGPoint] {
        let R = rand(seed)
        let a0 = R() * 2 * .pi, n = max(12, Int((r * 1.3).rounded())), k1 = R() * 2 * .pi, k2 = R() * 2 * .pi
        let e = 1 + (R() - 0.5) * 0.1
        var pts: [CGPoint] = []
        var i = 0
        while Double(i) <= Double(n) * (1 + over) {
            let a = a0 + Double(i) / Double(n) * 2 * .pi
            let rr = r * (1 + amp * (0.6 * sin(a * 2 + k1) + 0.4 * sin(a * 3 + k2))) * (1 + 0.035 * Double(i) / Double(n))
            pts.append(CGPoint(x: cx + cos(a) * rr * e, y: cy + sin(a) * rr / e))
            i += 1
        }
        return pts
    }

    static func blobPts(_ cx: Double, _ cy: Double, _ r: Double, _ seed: Int, amp: Double = 0.07) -> [CGPoint] {
        let R = rand(seed)
        let n = max(10, Int((r * 1.1).rounded())), k1 = R() * 2 * .pi, k2 = R() * 2 * .pi
        return (0..<n).map { i in
            let a = Double(i) / Double(n) * 2 * .pi
            let rr = r * (1 + amp * (0.6 * sin(a * 2 + k1) + 0.4 * sin(a * 3 + k2)))
            return CGPoint(x: cx + cos(a) * rr, y: cy + sin(a) * rr)
        }
    }

    static func poly(_ pts: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(pts)
        p.closeSubpath()
        return p
    }

    /// A short hatching stroke, a little bowed, as a pen makes it.
    static func hatch(_ x: Double, _ y: Double, _ dx: Double, _ dy: Double, _ bow: Double, into p: inout Path) {
        p.move(to: CGPoint(x: x, y: y))
        p.addQuadCurve(to: CGPoint(x: x + dx, y: y + dy),
                       control: CGPoint(x: x + dx / 2 - dy * bow, y: y + dy / 2 + dx * bow))
    }

    /// A path written with relative cubic segments, as the sketch's small SVG shapes are.
    static func relative(from start: CGPoint, _ segs: [(Double, Double, Double, Double, Double, Double)]) -> Path {
        var p = Path()
        var cur = start
        p.move(to: cur)
        for s in segs {
            let end = CGPoint(x: cur.x + s.4, y: cur.y + s.5)
            p.addCurve(to: end, control1: CGPoint(x: cur.x + s.0, y: cur.y + s.1),
                       control2: CGPoint(x: cur.x + s.2, y: cur.y + s.3))
            cur = end
        }
        return p
    }
}

private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

// MARK: - Palette

/// The painting's own colours (the sketch's `.stage` and `.stage.night`): a dusk-lit sky by day, a dark
/// one by night, whatever the panel around it.
struct MeltPalette {
    var night: Bool
    var paper, line, ink3, gold, goldInk, rose: Color
    var sunHi, sun, sunLo, grain, slice: Color
    var starHi, star, starLo, starlit: Color
    var sky1, sky2, sky3, cloud, sea, plain1, plain2, plain3: Color
    var stone, stone2, stone3, cliff, cliffLit, bark, wood2: Color
    var dial, dial2, dialInk, brassHi, beast, stick, stick2, bronze, rust, ochre, hollow: Color
    var shade, veil, glassTint, halo, tag, tagInk, tagInk3, mark: Color

    static let day = MeltPalette(
        night: false,
        paper: meltRGB(0xF3E8D6), line: meltRGB(0x2A1D17), ink3: meltRGB(0x2A1D17, 0.66), gold: meltRGB(0x8A4F08),
        goldInk: meltRGB(0x7A4507), rose: meltRGB(0xA3402F),
        sunHi: meltRGB(0xFFE3A6), sun: meltRGB(0xEEAE45), sunLo: meltRGB(0xCF7A28), grain: meltRGB(0x783E0A, 0.34), slice: meltRGB(0xFFF6DC),
        starHi: meltRGB(0xD3DDF2), star: meltRGB(0x90A4CC), starLo: meltRGB(0x53689A), starlit: .white,
        sky1: meltRGB(0x869FBE), sky2: meltRGB(0xD79E98), sky3: meltRGB(0xF0B979), cloud: meltRGB(0xF8E1CF),
        sea: meltRGB(0x9FB6CB), plain1: meltRGB(0xECD09C), plain2: meltRGB(0xDCB684), plain3: meltRGB(0xE3CBA6),
        stone: meltRGB(0xC99A76), stone2: meltRGB(0x946852), stone3: meltRGB(0xECC18C), cliff: meltRGB(0xA26C52), cliffLit: meltRGB(0xECAB6A),
        bark: meltRGB(0x43302A), wood2: meltRGB(0xA65D4B),
        dial: meltRGB(0xF6EED9), dial2: meltRGB(0xC9C7C0), dialInk: meltRGB(0x2F2219), brassHi: meltRGB(0xF2D496), beast: meltRGB(0x2A1D17),
        stick: meltRGB(0xB39270), stick2: meltRGB(0x86684F), bronze: meltRGB(0xB98B50), rust: meltRGB(0x9C4A33), ochre: meltRGB(0xE2A65A),
        hollow: meltRGB(0x4A2A1C),
        shade: meltRGB(0x44396A), veil: meltRGB(0x1F2A4A), glassTint: meltRGB(0xECF2F6, 0.5), halo: meltRGB(0xFFF8EC, 0.72),
        tag: meltRGB(0xF9EFDC), tagInk: meltRGB(0x2A1D17), tagInk3: meltRGB(0x2A1D17, 0.62), mark: meltRGB(0x417B7D))

    static let nightTime: MeltPalette = {
        var p = MeltPalette.day
        p.night = true
        p.paper = meltRGB(0x1B1822); p.line = meltRGB(0xF1E2C6); p.ink3 = meltRGB(0xF0E3CB, 0.62)
        p.gold = meltRGB(0xF0B24F); p.rose = meltRGB(0xF0907A)
        p.sunHi = meltRGB(0xFFDC92); p.sun = meltRGB(0xE8A33A); p.sunLo = meltRGB(0xBD6B1D); p.grain = meltRGB(0x5E2E04, 0.36); p.slice = meltRGB(0xFFF3D2)
        p.sky1 = meltRGB(0x1D2440); p.sky2 = meltRGB(0x4B3352); p.sky3 = meltRGB(0x9C603C); p.cloud = meltRGB(0x6E4C5C)
        p.sea = meltRGB(0x3E4B68); p.plain1 = meltRGB(0x6E5038); p.plain2 = meltRGB(0x4A372A); p.plain3 = meltRGB(0x2C241F)
        p.stone = meltRGB(0x7A5A46); p.stone2 = meltRGB(0x4A3529); p.stone3 = meltRGB(0xA8774F); p.cliff = meltRGB(0x4C372F); p.cliffLit = meltRGB(0xB26A3C)
        p.bark = meltRGB(0x120D10); p.wood2 = meltRGB(0x6E3A2E)
        p.dial = meltRGB(0xD9CFB6); p.dial2 = meltRGB(0x8A9CB0); p.dialInk = meltRGB(0x2A1D17); p.brassHi = meltRGB(0xD9B878); p.beast = meltRGB(0x07050B)
        p.stick = meltRGB(0x8A6E55); p.stick2 = meltRGB(0x5A4636); p.bronze = meltRGB(0x9A7444); p.rust = meltRGB(0xC9785A); p.ochre = meltRGB(0xB9803F)
        p.hollow = meltRGB(0x0C0810)
        p.shade = meltRGB(0x06040C); p.veil = meltRGB(0x0B1023); p.glassTint = meltRGB(0xAABEE1, 0.10); p.halo = meltRGB(0x161320, 0.7)
        p.mark = meltRGB(0x86CACE)
        return p
    }()
}

func meltRGB(_ v: UInt32, _ alpha: Double = 1) -> Color {
    Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
          blue: Double(v & 0xFF) / 255, opacity: alpha)
}

// MARK: - Faces

/// System faces, chosen as the sketch's own fallbacks: New York for the display numerals (for
/// Fraunces), American Typewriter for the small labels (for Special Elite), Bradley Hand for the
/// handwritten notes (for Caveat) and Iowan Old Style italic for the caption (for IM Fell English).
/// All ship with macOS, so nothing is bundled.
enum MeltFont {
    static func type(_ size: CGFloat) -> Font { .custom("AmericanTypewriter", fixedSize: size) }
    static func hand(_ size: CGFloat) -> Font { .custom("BradleyHandITCTT-Bold", fixedSize: size) }
    static func caption(_ size: CGFloat) -> Font { .custom("IowanOldStyle-Italic", fixedSize: size) }
    static func captionRoman(_ size: CGFloat) -> Font { .custom("IowanOldStyle-Roman", fixedSize: size) }
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Textures

/// Noise images made once: the paper's tooth and the blotches of a wash. Deterministic, so every
/// render is the same.
enum MeltTexture {
    static let tooth: CGImage = noise(width: 160, height: 160, octaves: [(80, 0.45), (40, 0.35), (20, 0.2)], seed: 9,
                                      tint: (0.36, 0.26, 0.16), gain: 0.55)
    /// The sketch's fMottle: fractal noise whose alpha is 2.2 × noise − 0.9, so only the blotches show.
    static let mottle: CGImage = noise(width: 96, height: 128, octaves: [(5, 0.55), (11, 0.3), (23, 0.15)], seed: 17,
                                       gain: 2.2, bias: -0.9)

    /// Grey value noise as an image whose alpha is the noise: `octaves` are (cells across, weight).
    private static func noise(width w: Int, height h: Int, octaves: [(Int, Double)], seed: Int,
                              tint: (Double, Double, Double) = (0, 0, 0), gain: Double = 1, bias: Double = 0) -> CGImage {
        let R = Hand.rand(seed)
        var grids: [(Int, [Double], Double)] = []
        for (cells, weight) in octaves {
            let n = cells + 2
            grids.append((cells, (0..<(n * n)).map { _ in R() }, weight))
        }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                var v = 0.0
                for (cells, g, weight) in grids {
                    let n = cells + 2
                    let fx = Double(x) / Double(w) * Double(cells), fy = Double(y) / Double(h) * Double(cells)
                    let ix = Int(fx), iy = Int(fy), tx = fx - Double(ix), ty = fy - Double(iy)
                    let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
                    let a = g[iy * n + ix], b = g[iy * n + ix + 1], c = g[(iy + 1) * n + ix], d = g[(iy + 1) * n + ix + 1]
                    v += weight * ((a * (1 - sx) + b * sx) * (1 - sy) + (c * (1 - sx) + d * sx) * sy)
                }
                let i = (y * w + x) * 4
                let a = max(0, min(1, v * gain + bias))
                px[i] = UInt8(tint.0 * a * 255); px[i + 1] = UInt8(tint.1 * a * 255); px[i + 2] = UInt8(tint.2 * a * 255)
                px[i + 3] = UInt8(a * 255)
            }
        }
        let data = CFDataCreate(nil, px, px.count)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)!
    }
}

// MARK: - The geometry

/// The glass's shape at one degree of melt (0 crisp at sunrise, 1 slumped at sunset), in scene units.
struct MeltGlass {
    static let CX = 212.0, yTop = 118.0, yNeck = 292.0, yBot = 470.0
    static let HB = yNeck - yTop, HB2 = yBot - yNeck
    static let WMAX = 84.0, WB = 90.0, NECK = 6.0, INSET = 1.6
    struct Ledge { static let x0 = 104.0, x1 = 314.0, top = 480.0, back = 464.0, dx = 14.0, foot = 540.0 }
    static let ground = Ledge.foot
    /// The dead tree, from its foot to the tip of the branch the glass hangs from.
    static let tree: [CGPoint] = [pt(34, 596), pt(29, 548), pt(37, 500), pt(27, 450), pt(23, 394), pt(32, 336),
                                  pt(26, 282), pt(35, 228), pt(48, 186), pt(62, 150), pt(86, 114), pt(120, 88),
                                  pt(160, 72), pt(200, 63), pt(240, 57), pt(282, 49), pt(322, 40)]
    static let elbow = 9, treeFoot = 596.0, elephantX = 336.0
    static let branchPts: [CGPoint] = Hand.spline(Array(tree[elbow...]), 2)

    /// The horizon's height at x: a long, slightly bowed line.
    static func hz(_ x: Double) -> Double {
        let t = x / 400
        return (1 - t) * (1 - t) * 409 + 2 * t * (1 - t) * 397 + t * t * 411
    }

    static func branchY(_ x: Double) -> Double {
        var best = branchPts[0]
        for p in branchPts where abs(p.x - x) < abs(best.x - x) { best = p }
        return best.y
    }

    let melt: Double
    private var area: [Double] = []
    private(set) var dialCenter: CGPoint = .zero
    private(set) var flapLow: Double = MeltGlass.yTop

    init(melt: Double) {
        self.melt = melt
        var a: [Double] = [0], sum = 0.0
        var i = 1
        while MeltGlass.yNeck - Double(i) * 0.25 >= MeltGlass.yTop - 1e-9 {
            let y = MeltGlass.yNeck - (Double(i) - 0.5) * 0.25
            sum += max(1.2, xRi(y) - xLi(y)) * 0.25
            a.append(sum)
            i += 1
        }
        area = a
        let cx = cT(MeltGlass.yTop) + 4
        dialCenter = CGPoint(x: cx, y: MeltGlass.branchY(cx) + MeltGlass.dialRY - 7)
        flapLow = dialRing(1).filter { $0.x < cx }.map { $0.y }.max() ?? MeltGlass.yTop
    }

    private func gp(_ t: Double) -> Double {
        let P = 0.7
        if t > P { return 1 - 0.6 * pow((t - P) / (1 - P), 2.2) }
        return 1 - pow(1 - t / P, 2.1)
    }
    private func g2(_ u: Double) -> Double {
        u < 0.84 ? 1 - pow(1 - u / 0.84, 2.1) : 1 - 0.16 * pow((u - 0.84) / 0.16, 2)
    }
    /// The top bulb is blown lopsided, left and right differently, with a dent low on the left.
    private func wT(_ y: Double, _ side: Double) -> Double {
        let t = min(1, max(0, (MeltGlass.yNeck - y) / MeltGlass.HB))
        let w = MeltGlass.NECK + (MeltGlass.WMAX - MeltGlass.NECK) * gp(t)
        let lump = side < 0 ? 0.05 * sin(t * 5.1 + 0.4) - 0.045 * exp(-pow((t - 0.42) / 0.1, 2))
                            : 0.04 * sin(t * 4.3 + 2.1)
        return w * (1 + lump * t)
    }
    /// As it softens the top leans left over the neck and the bottom slumps right, like a reed.
    func cT(_ y: Double) -> Double {
        MeltGlass.CX - (6 + 7 * melt) * pow(min(1, max(0, (MeltGlass.yNeck - y) / MeltGlass.HB)), 1.6)
    }
    func bx(_ u: Double) -> Double { MeltGlass.CX + (8 + 22 * melt) * u * u }
    private func bw(_ u: Double) -> Double { MeltGlass.NECK + (MeltGlass.WB - MeltGlass.NECK) * g2(u) }

    func xL(_ y: Double) -> Double {
        if y <= MeltGlass.yNeck { return cT(y) - wT(y, -1) }
        let u = min(1, (y - MeltGlass.yNeck) / MeltGlass.HB2)
        return bx(u) - bw(u) * (1 - 0.04 * melt * u * u)
    }
    func xR(_ y: Double) -> Double {
        if y <= MeltGlass.yNeck { return cT(y) + wT(y, 1) }
        let u = min(1, (y - MeltGlass.yNeck) / MeltGlass.HB2)
        return bx(u) + bw(u) * (1 + (0.1 + 0.22 * melt) * pow(u, 2.5))
    }
    func xLi(_ y: Double) -> Double { xL(y) + MeltGlass.INSET }
    func xRi(_ y: Double) -> Double { xR(y) - MeltGlass.INSET }
    func midI(_ y: Double) -> Double { (xLi(y) + xRi(y)) / 2 }

    struct Lobe { var lobe: Double; var tip: CGPoint; var xr: Double; var knots: [CGPoint] }
    /// Where the bottom bulb runs past the ledge it sags over it, a soft lobe with light in its tip.
    func lobe() -> Lobe? {
        let L = MeltGlass.Ledge.self
        let yb = MeltGlass.yBot - 6, xr = xR(yb), spill = min(1, max(0, (xr - (L.x1 - 10)) / 34))
        if spill < 0.15 { return nil }
        let lobe = 6 + 48 * spill * (0.45 + 0.55 * melt), xo = max(xr, L.x1 + 14)
        let tip = pt((L.x1 + xo) / 2 + 4, L.top + lobe)
        return Lobe(lobe: lobe, tip: tip, xr: xr, knots: [
            pt(L.x1 - 3, MeltGlass.yBot + 1), pt(L.x1 + 1.5, L.top + 3), pt(L.x1 + 3, L.top + lobe * 0.55), tip,
            pt(xo + 2 + 3 * melt, L.top + lobe * 0.5), pt(xo + 4 + 4 * melt, L.top - 3), pt(xr, yb)])
    }

    /// The whole outline of the glass, top left round to top right.
    func outline() -> [CGPoint] {
        var out: [CGPoint] = []
        var y = MeltGlass.yTop
        while y <= MeltGlass.yBot + 0.01 { out.append(pt(xL(y), y)); y += 4 }
        if let lb = lobe() {
            let b0 = xL(MeltGlass.yBot), b1 = lb.knots[0].x
            for k in 1..<8 { out.append(pt(b0 + (b1 - b0) * Double(k) / 8, MeltGlass.yBot + 1.5 * sin(.pi * Double(k) / 8))) }
            out += Hand.spline(lb.knots, 3).dropLast()
            y = MeltGlass.yBot - 6
        } else {
            let b0 = xL(MeltGlass.yBot), b1 = xR(MeltGlass.yBot)
            for k in 1..<10 { out.append(pt(b0 + (b1 - b0) * Double(k) / 10, MeltGlass.yBot + 2 * sin(.pi * Double(k) / 10))) }
            y = MeltGlass.yBot
        }
        while y >= MeltGlass.yTop - 0.01 { out.append(pt(xR(y), y)); y -= 4 }
        return out
    }

    /// The top bulb's sand by area, so the share of glass filled is the share of light left.
    func levelY(_ fraction: Double) -> Double {
        let target = min(1, max(0, fraction)) * (area.last ?? 0)
        var lo = 0, hi = area.count - 1
        while hi - lo > 1 {
            let m = (lo + hi) >> 1
            if area[m] < target { lo = m } else { hi = m }
        }
        let a0 = area[lo], a1 = area[hi], k = a1 > a0 ? (target - a0) / (a1 - a0) : 0
        return max(MeltGlass.yTop, MeltGlass.yNeck - (Double(lo) + k) * 0.25)
    }

    private func ys(_ y0: Double, _ y1: Double) -> [Double] {
        var out: [Double] = []
        var y = y0
        while y < y1 { out.append(y); y += 1.5 }
        out.append(y1)
        return out
    }
    /// The inside of the top bulb between y0 and y1; `dip` hollows the surface where sand drains.
    func band(_ y0: Double, _ y1: Double, dip: Double) -> Path {
        let Y = ys(y0, y1)
        var p = Path()
        p.move(to: pt(xLi(y0), y0))
        for y in Y.dropFirst() { p.addLine(to: pt(xLi(y), y)) }
        for y in Y.reversed() { p.addLine(to: pt(xRi(y), y)) }
        if dip > 0.2 { p.addQuadCurve(to: pt(xLi(y0), y0), control: pt(midI(y0), y0 + 2 * dip)) }
        p.closeSubpath()
        return p
    }
    /// A layer whose top and bottom are both hollowed by dip, so a thin slice keeps its thickness.
    func layer(_ y0: Double, _ y1: Double, dip: Double) -> Path {
        let Y = ys(y0, y1)
        var p = Path()
        p.move(to: pt(xLi(y0), y0))
        for y in Y.dropFirst() { p.addLine(to: pt(xLi(y), y)) }
        let bd = y1 >= MeltGlass.yNeck - 1 ? 0 : dip
        p.addQuadCurve(to: pt(xRi(y1), y1), control: pt(midI(y1), y1 + 2 * bd))
        for y in Y.dropLast().reversed() { p.addLine(to: pt(xRi(y), y)) }
        if dip > 0.2 { p.addQuadCurve(to: pt(xLi(y0), y0), control: pt(midI(y0), y0 + 2 * dip)) }
        p.closeSubpath()
        return p
    }

    struct Slot { var x: Double; var y: Double }
    /// Places for the finished blocks, filling the slumped bottom bulb as a mound under the stream.
    func slots(_ d: Double) -> [Slot] {
        let rmax = 0.46 * d, rowH = 0.88 * d
        var out: [Slot] = []
        var y = MeltGlass.yBot - rmax - 3, prevM = -1
        while y > MeltGlass.yNeck + 44 {
            let yy = [y - rmax, y, min(MeltGlass.yBot - 1, y + rmax)]
            let lo = yy.map(xLi).max()! + rmax + 2.5
            let hi = min(MeltGlass.Ledge.x1 - 4, yy.map(xRi).min()!) - rmax - 2.5
            if hi >= lo {
                var m = Int(floor((hi - lo) / d)) + 1
                if m > 1 && prevM > 0 && m % 2 == prevM % 2 { m -= 1 }
                let mid = min(max(MeltGlass.CX, lo + Double(m - 1) * d / 2), hi - Double(m - 1) * d / 2)
                for j in 0..<m { out.append(Slot(x: mid + (Double(j) - Double(m - 1) / 2) * d, y: y)) }
                prevM = m
            }
            y -= rowH
        }
        func mound(_ s: Slot) -> Double { (MeltGlass.yBot - s.y) + 0.7 * abs(s.x - MeltGlass.CX) }
        return out.sorted { mound($0) != mound($1) ? mound($0) < mound($1) : $0.x < $1.x }
    }
    static func discR(_ seconds: Double, _ d: Double) -> Double {
        d * (0.2 + 0.26 * sqrt(min(seconds, 7200) / 7200))
    }

    // The soft watch the glass hangs from. Its face counts the hours to the horizon, −1 to −11 round
    // from the top, where the sun sits on its line; its one hand stands at the tilset now (the tilrise
    // at night). Thrown over the branch, its left side runs off like warm wax, further as light runs out.
    static let dialRX = 84.0, dialRY = 40.0, dialTilt = -0.14

    func dialAt(_ u0: Double, _ v0: Double) -> CGPoint {
        let m = melt
        let rr = hypot(u0, v0), an = atan2(u0, -v0)
        let rip = 1 + (0.025 + 0.03 * m) * pow(rr, 3) * sin(an * 5 + 1.3)
        let u = u0 * rip, v = v0 * rip
        var x = MeltGlass.dialRX * u, y = MeltGlass.dialRY * v
        y += (3 + 10 * m) * (1 + v) * 0.5 * max(0, 1 - u * u)
        let uu = -0.24
        if u < uu {
            let k = (uu - u) / (1 + uu)
            y += (40 + 46 * m) * pow(k, 1.45) * (0.5 + 0.5 * (1 + v) / 2)
            x = uu * MeltGlass.dialRX + (x - uu * MeltGlass.dialRX) * (1 - 0.42 * k * (0.55 + 0.45 * m))
        }
        if u > 0.55 { y -= 6 * pow((u - 0.55) / 0.45, 2) * (1 - v) * 0.5 }
        let c = cos(MeltGlass.dialTilt), s = sin(MeltGlass.dialTilt)
        return pt(dialCenter.x + x * c - y * s, dialCenter.y + x * s + y * c)
    }
    static func polar(_ r: Double, _ a: Double) -> (Double, Double) { (r * sin(a), -r * cos(a)) }
    func dialRing(_ r: Double, _ n: Int = 120) -> [CGPoint] {
        (0..<n).map { i in let p = MeltGlass.polar(r, Double(i) / Double(n) * 2 * .pi); return dialAt(p.0, p.1) }
    }
}

// MARK: - What the painting shows

/// The part of a snapshot the painting draws, rounded so the canvas redraws when something visible
/// moves rather than every second.
struct MeltScene: Equatable {
    var phase: LightGlass.Phase?
    var share: Double          // top bulb, 0...1
    var span: Double           // seconds of this light (or night)
    var layer: Double          // the block's (or the preview's) share
    var layerKind: LayerKind
    var leftText: String       // "3 h 45 m"
    var layerText: String?     // "15 m"
    var layerWarn: Bool
    var passedText: String?
    var startClock: String?
    var edgeClock: String?
    var suns: Int
    var tallyText: String?     // "1 h 40 m"
    var tallyOfLight: Bool
    var progress: Double       // of the running focus block, for the sun forming in the bottom bulb
    var formingFocus: Bool

    enum LayerKind: Equatable { case none, preview, focus, paused, rest, longRest }

    var flowing: Bool { layerKind == .focus || layerKind == .rest || layerKind == .longRest }
    var night: Bool { phase == .night }
    /// 0 crisp (sunrise), 1 slumped (sunset); it sets again through the night. In 40 steps, as the sketch.
    var melt: Double {
        guard let ph = phase else { return 0 }
        let m = ph == .day ? 1 - share : share
        return (min(1, max(0, m)) * 40).rounded() / 40
    }

    init(_ s: LightGlass.Snapshot) {
        phase = s.phase
        share = (s.topShare * 4000).rounded() / 4000
        span = s.skySpan
        func strip(_ t: String) -> String {
            t.replacingOccurrences(of: " of light left", with: "").replacingOccurrences(of: " until sunrise", with: "")
        }
        leftText = strip(s.leftText)
        passedText = s.passedText
        startClock = s.startClock
        edgeClock = s.edgeClock
        suns = s.suns
        let light = s.tally.lightSeconds, night = s.tally.nightSeconds
        tallyOfLight = light >= night
        tallyText = s.suns > 0 ? LightGlass.span(tallyOfLight ? light : night) : nil
        progress = (s.progress * 200).rounded() / 200
        layerWarn = false
        switch s.mode {
        case .running, .paused:
            layer = (s.blockShare * 4000).rounded() / 4000
            layerText = s.remainingSpan
            layerWarn = s.warning != nil
            if s.isRest { layerKind = s.title == "Long break" ? .longRest : .rest }
            else { layerKind = s.mode == .paused ? .paused : .focus }
            if s.mode == .paused && s.isRest { layerKind = .paused }
            formingFocus = !s.isRest
        case .idle:
            formingFocus = false
            if let n = s.next {
                layer = (n.share * 4000).rounded() / 4000
                layerText = n.span
                layerWarn = n.warning != nil
                layerKind = .preview
            } else {
                layer = 0; layerText = nil; layerKind = .none
            }
        }
    }
}

// MARK: - The painting

struct MeltingGlassPainting: View, Equatable {
    let scene: MeltScene

    /// The part of the sketch's 400 × 580 canvas the popover shows: the whole picture, less a little sky
    /// and the plain's last strip.
    static let crop = CGRect(x: 6, y: 30, width: 388, height: 546)
    static func height(forWidth w: CGFloat) -> CGFloat { (w * crop.height / crop.width).rounded() }

    var body: some View {
        Canvas { ctx, size in
            MeltDrawing(scene: scene, size: size).draw(&ctx)
        }
    }
}

/// The parts that move: the stream through the neck and the drip off the lobe. Drawn on their own small
/// canvas so only they redraw while they animate, and not at all under Reduce Motion.
struct MeltingGlassMotion: View {
    let scene: MeltScene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || scene.phase == nil)) { tl in
            Canvas { ctx, size in
                MeltDrawing(scene: scene, size: size).drawMotion(&ctx, time: reduceMotion ? nil : tl.date.timeIntervalSinceReferenceDate)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MeltDrawing {
    let scene: MeltScene
    let size: CGSize
    let p: MeltPalette
    let g: MeltGlass
    let k: CGFloat   // points per scene unit

    init(scene: MeltScene, size: CGSize) {
        self.scene = scene
        self.size = size
        p = scene.night ? .nightTime : .day
        g = MeltGlass(melt: scene.melt)
        k = size.width / MeltingGlassPainting.crop.width
    }

    typealias G = MeltGlass
    typealias L = MeltGlass.Ledge

    /// Scene units to points.
    func v(_ q: CGPoint) -> CGPoint {
        CGPoint(x: (q.x - MeltingGlassPainting.crop.minX) * k, y: (q.y - MeltingGlassPainting.crop.minY) * k)
    }

    func scaled(_ ctx: GraphicsContext) -> GraphicsContext {
        var c = ctx
        c.scaleBy(x: k, y: k)
        c.translateBy(x: -MeltingGlassPainting.crop.minX, y: -MeltingGlassPainting.crop.minY)
        return c
    }

    // MARK: drawing primitives (scene units)

    func stroke(_ c: GraphicsContext, _ path: Path, _ color: Color, _ w: Double, dash: [CGFloat] = [], phase: CGFloat = 0) {
        c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round,
                                                               dash: dash, dashPhase: phase))
    }

    /// An inked line: a firm pass and a fainter second pass that does not quite agree with it.
    func ink(_ c: GraphicsContext, _ pts: [CGPoint], w: Double = 1.4, amp: Double = 1, seed: Int = 1, wl: Double = 24,
             closed: Bool = false, over: Double = 2.5, ghost: Bool = true, color: Color? = nil, opacity: Double = 1) {
        let col = (color ?? p.line).opacity(opacity)
        let P = closed ? pts : Hand.extend(pts, over * (0.6 + Hand.rand(seed)() * 0.8), over * (0.4 + Hand.rand(seed + 7)() * 0.9))
        stroke(c, Hand.curve(Hand.wobble(P, amp, seed, wl), closed: closed), col, w)
        if ghost {
            stroke(c, Hand.curve(Hand.wobble(P, amp * 1.35, seed + 101, wl * 0.8), closed: closed), col.opacity(0.42), w * 0.55)
        }
    }

    /// A brushed line: a filled stroke that swells and thins with the wrist and lifts off at its ends.
    func brush(_ c: GraphicsContext, _ pts: [CGPoint], w: Double = 2.4, amp: Double = 1, seed: Int = 1, wl: Double = 24,
               closed: Bool = false, over: Double = 2.5, vary: Double = 0.5, ghost: Bool = true, color: Color? = nil) {
        let col = color ?? p.line
        let P = Hand.wobble(closed ? pts : Hand.extend(pts, over * (0.6 + Hand.rand(seed)() * 0.8),
                                                       over * (0.4 + Hand.rand(seed + 7)() * 0.9)), amp, seed, wl)
        let n = P.count
        let R = Hand.rand(seed + 33)
        let K = (0..<Int(ceil(Double(n) / 5 + 4))).map { _ in R() }
        func ip(_ q: Double) -> Double {
            let kk = Int(floor(q)), fr = q - Double(kk)
            let a = K[kk % K.count], b = K[(kk + 1) % K.count]
            return a + (b - a) * (1 - cos(fr * .pi)) / 2
        }
        var A: [CGPoint] = [], B: [CGPoint] = []
        for i in 0..<n {
            let q0 = P[closed ? (i - 1 + n) % n : max(0, i - 1)], q1 = P[closed ? (i + 1) % n : min(n - 1, i + 1)]
            var nx = q0.y - q1.y, ny = q1.x - q0.x
            let l = hypot(nx, ny) == 0 ? 1 : hypot(nx, ny)
            nx /= l; ny /= l
            var hw = w / 2 * (1 - vary + 2 * vary * ip(Double(i) / 5))
            if !closed {
                let e = Double(min(i, n - 1 - i)) / min(10, Double(n) / 2)
                hw *= min(1, 0.15 + 0.85 * e)
            }
            A.append(pt(P[i].x + nx * hw, P[i].y + ny * hw))
            B.append(pt(P[i].x - nx * hw, P[i].y - ny * hw))
        }
        var path = Path()
        if closed {
            Hand.curve(A, closed: true, into: &path)
            Hand.curve(B, closed: true, into: &path)
            c.fill(path, with: .color(col), style: FillStyle(eoFill: true))
        } else {
            Hand.curve(A + B.reversed(), closed: true, into: &path)
            c.fill(path, with: .color(col))
        }
        if ghost { stroke(c, Hand.curve(Hand.wobble(P, amp * 1.5, seed + 101, wl * 0.8), closed: closed), col.opacity(0.42), w * 0.32) }
    }

    /// A wash of colour, as the sketch's fWash: a fill that lets a little of what is under it through,
    /// pooled darker in blotches and at its rim.
    func wash(_ c: GraphicsContext, _ path: Path, _ shading: GraphicsContext.Shading, rim: Color, opacity: Double = 1) {
        var cc = c
        cc.opacity = opacity * 0.86
        cc.fill(path, with: shading)
        cc.opacity = opacity
        let b = path.boundingRect
        var blot = cc
        blot.clip(to: path)
        blot.clipToLayer { m in
            m.draw(Image(decorative: MeltTexture.mottle, scale: 1).resizable(),
                   in: CGRect(x: b.minX - 40, y: b.minY - 30, width: max(b.width, 160) + 80, height: max(b.height, 160) + 60))
        }
        blot.fill(path, with: .color(rim.opacity(0.22)))
        cc.stroke(path, with: .color(rim.opacity(0.32)), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
    }

    // MARK: words (points, set at fixed sizes)

    enum Anchor { case start, middle, end }

    /// Draws a line of words with its baseline at a scene point.
    func say(_ ctx: GraphicsContext, _ text: Text, at q: CGPoint, _ anchor: Anchor = .start, halo: Text? = nil,
             dx: CGFloat = 0, dy: CGFloat = 0) {
        let r = ctx.resolve(text)
        let sz = r.measure(in: CGSize(width: 1000, height: 200))
        let base = r.firstBaseline(in: sz)
        let o = v(q)
        let x = o.x + dx - (anchor == .start ? 0 : anchor == .middle ? sz.width / 2 : sz.width)
        let rect = CGRect(x: x, y: o.y + dy - base, width: sz.width, height: sz.height)
        if let h = halo {
            let hr = ctx.resolve(h)
            for (ox, oy) in [(-1.0, 0.0), (1, 0), (0, -1), (0, 1), (-0.7, -0.7), (0.7, 0.7), (-0.7, 0.7), (0.7, -0.7)] {
                ctx.draw(hr, in: rect.offsetBy(dx: ox, dy: oy))
            }
        }
        ctx.draw(r, in: rect)
    }

    func width(_ ctx: GraphicsContext, _ text: Text) -> CGFloat {
        ctx.resolve(text).measure(in: CGSize(width: 1000, height: 200)).width
    }

    func cap(_ s: String, _ color: Color? = nil, size: CGFloat = 7.2) -> Text {
        Text(s).font(MeltFont.type(size)).tracking(0.7).foregroundColor(color ?? p.ink3)
    }
    func handText(_ s: String, _ color: Color? = nil, size: CGFloat = 12.5) -> Text {
        Text(s).font(MeltFont.hand(size)).tracking(-0.3).foregroundColor(color ?? p.line)
    }

    // MARK: - The whole picture

    func draw(_ ctx: inout GraphicsContext) {
        let c = scaled(ctx)
        // The painting, inside its ragged edge.
        let edge = raggedEdge()
        var painted = c
        painted.clip(to: edge)
        drawScene(painted)
        // The paper's edge, where the wash stops.
        stroke(c, edge, p.line.opacity(p.night ? 0.25 : 0.12), 0.8)

        // The instrument, unmasked, so the bell and the tags may cross the edge.
        drawGlassBack(c)
        drawSand(c)
        if scene.phase != nil && !scene.flowingAnimatable { drawStream(c, phase: 0) }
        drawBottom(c)
        drawScale(ctx, c)
        drawFront(c)
        drawHand(c)
        drawLabels(ctx, c)
    }

    func drawMotion(_ ctx: inout GraphicsContext, time: Double?) {
        guard scene.phase != nil else { return }
        let c = scaled(ctx)
        if scene.flowingAnimatable { drawStream(c, phase: time ?? 0) }
        drawDrip(c, time: time)
    }

    func raggedEdge() -> Path {
        let r = CGRect(x: 10, y: 33, width: 380, height: 540)
        let rr = Path(roundedRect: r, cornerRadius: 12)
        // the rounded rect's outline, sampled and torn a little
        var pts: [CGPoint] = []
        let corners: [(CGPoint, CGPoint)] = [
            (pt(r.minX + 12, r.minY), pt(r.maxX - 12, r.minY)), (pt(r.maxX, r.minY + 12), pt(r.maxX, r.maxY - 12)),
            (pt(r.maxX - 12, r.maxY), pt(r.minX + 12, r.maxY)), (pt(r.minX, r.maxY - 12), pt(r.minX, r.minY + 12))]
        for (a, b) in corners { pts += Hand.dense([a, b], 3).dropLast() }
        _ = rr
        return Hand.curve(Hand.wobble(Hand.wobble(pts, 2.6, 19, 14), 0.9, 23, 4), closed: true)
    }
}

extension MeltScene {
    /// The stream animates only while light is pouring for a block or break.
    var flowingAnimatable: Bool { flowing }
}

// MARK: - The scene: sky, sea, cliffs, the plain, the ledge and the dead tree

private extension MeltDrawing {
    func drawScene(_ c: GraphicsContext) {
        let R = Hand.rand(1931)
        let H0: [CGPoint] = stride(from: -14.0, through: 414, by: 6).map { pt($0, G.hz($0)) }
        var sky = Path()
        sky.move(to: pt(-14, 0)); sky.addLine(to: pt(414, 0)); sky.addLine(to: pt(414, G.hz(414)))
        for q in H0.reversed() { sky.addLine(to: q) }
        sky.closeSubpath()
        var ground = Path()
        ground.move(to: pt(-14, G.hz(-14)))
        for q in H0 { ground.addLine(to: q) }
        ground.addLine(to: pt(414, 610)); ground.addLine(to: pt(-14, 610)); ground.closeSubpath()

        let all = CGRect(x: -14, y: 0, width: 428, height: 612)
        c.fill(Path(all), with: .color(p.paper))
        c.fill(Path(CGRect(x: -14, y: 0, width: 428, height: 420)),
               with: .linearGradient(Gradient(stops: [.init(color: p.sky1, location: 0), .init(color: p.sky2, location: 0.58),
                                                      .init(color: p.sky3, location: 1)]),
                                     startPoint: pt(0, 10), endPoint: pt(0, 410)))
        mottle(c, Path(CGRect(x: -14, y: 0, width: 428, height: 420)), p.sky2, 0.45)
        mottle(c, Path(CGRect(x: -14, y: 200, width: 428, height: 220)), p.sky3, 0.4, seedShift: 0.37)

        // clouds: a few long thin streaks, as in the Catalan skies
        for (x0, x1, y, h) in [(214.0, 420.0, 150.0, 5.0), (-20, 150, 206, 4), (236, 420, 318, 3.4), (-20, 96, 352, 2.6), (120, 250, 44, 3)] {
            var top: [CGPoint] = [], bot: [CGPoint] = []
            var x = x0
            while x <= x1 {
                let kk = sin(.pi * (x - x0) / (x1 - x0))
                top.append(pt(x, y - h * kk + sin(x * 0.05) * 0.8)); bot.append(pt(x, y + h * 0.6 * kk))
                x += 8
            }
            wash(c, Hand.curve(top + bot.reversed(), closed: true), .color(p.cloud.opacity(0.75)), rim: p.cloud)
        }

        // the sun where it stands, clipped to the sky
        var skyC = c
        skyC.clip(to: sky)
        drawSun(skyC)

        // the sea, a pale band under the far right, and the cliffs of the cape
        var seaTop: [CGPoint] = [], seaBot: [CGPoint] = []
        var x = 206.0
        while x <= 414 {
            seaTop.append(pt(x, G.hz(x) - 0.2))
            seaBot.append(pt(x, G.hz(x) + 3 + min(1, (x - 206) / 60) * 7 + sin(x * 0.2) * 0.7))
            x += 6
        }
        wash(c, Hand.curve(seaTop + seaBot.reversed(), closed: true), .color(p.sea), rim: p.sea)
        drawGlint(c)
        let cliffK = [pt(352, G.hz(352) + 9), pt(356, 396), pt(361, 384), pt(367, 387), pt(372, 371), pt(379, 362),
                      pt(386, 366), pt(392, 352), pt(400, 347), pt(414, 345), pt(414, G.hz(414) + 12)]
        var cliff = Hand.curve(Hand.spline(cliffK, 3))
        cliff.closeSubpath()
        wash(c, cliff, .color(p.cliff), rim: p.cliff)
        ink(c, Hand.spline([pt(361, 386), pt(367, 388), pt(372, 373), pt(379, 364)], 2), w: 1.6, amp: 0.5, seed: 71,
            ghost: false, color: p.cliffLit)
        stroke(c, Hand.curve(Hand.wobble(Hand.spline(cliffK, 3), 0.6, 77, 10)), p.line, 1)

        // the plain
        wash(c, ground, .linearGradient(Gradient(stops: [.init(color: p.plain1, location: 0), .init(color: p.plain2, location: 0.55),
                                                         .init(color: p.plain3, location: 1)]),
                                        startPoint: pt(0, 400), endPoint: pt(0, 600)), rim: p.plain2)
        mottle(c, Path(CGRect(x: -14, y: 400, width: 428, height: 210)), p.plain2, 0.5, seedShift: 0.61)
        stroke(c, Hand.curve(Hand.wobble(H0, 0.5, 11, 30)), p.line.opacity(0.7), 0.9)

        // dry-brush strokes, close at the horizon and wider towards us; then a stipple of sand
        var off = 2.2, gap = 1.6, row = 0
        while off < 200 {
            let n = row < 8 ? 4 + Int(floor(R() * 4)) : 1 + Int(floor(R() * 3))
            for i in 0..<n {
                let x0 = R() * 440 - 20, len = 8 + R() * 30 * (1 + Double(row) * 0.06)
                var pts: [CGPoint] = []
                var xx = x0
                while xx < x0 + len { pts.append(pt(xx, G.hz(xx) + off + (R() - 0.5) * gap * 0.3)); xx += 5 }
                if pts.count > 1 {
                    stroke(c, Hand.curve(Hand.wobble(pts, 0.22, 900 + row * 13 + i, 30)),
                           p.line.opacity(0.13 + Double(row) * 0.008), 0.45 + Double(row) * 0.04)
                }
            }
            off += gap; gap *= 1.2; row += 1
        }
        for _ in 0..<260 {
            let x = R() * 420 - 10, kk = pow(R(), 0.6), y = G.hz(x) + 6 + kk * 190
            let r = 0.3 + kk * 0.7 * R()
            c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(p.line.opacity(0.1 + kk * 0.16)))
        }
        for (sx, sy, r) in [(176.0, 428.0, 2.2), (312, 437, 1.6), (64, 452, 2.8), (362, 470, 3.2), (250, 418, 1.2), (104, 424, 1.1), (384, 548, 4), (160, 566, 3.4)] {
            c.fill(Path(ellipseIn: CGRect(x: sx - r * 1.5, y: sy - r * 0.7, width: r * 3, height: r * 1.4)), with: .color(p.stone2.opacity(0.8)))
            stroke(c, Hand.curve(Hand.wobble([pt(sx - r * 1.5, sy), pt(sx - r * 0.5, sy - r * 0.8), pt(sx + r * 0.9, sy - r * 0.6), pt(sx + r * 1.5, sy)], 0.3, Int(sx), 6)),
                   p.line.opacity(0.7), 0.7)
        }
        for cc in 0..<6 {
            var xx = 70 + R() * 300, yy = 556 + R() * 30
            var pts = [pt(xx, yy)]
            for _ in 0..<4 { xx += 7 + R() * 12; yy += (R() - 0.5) * 8; pts.append(pt(xx, yy)) }
            stroke(c, Hand.curve(Hand.wobble(Hand.dense(pts, 3), 0.6, 300 + cc, 8)), p.line.opacity(0.35), 0.7)
        }

        var groundC = c
        groundC.clip(to: ground)
        drawShadows(groundC)
        var band = c
        band.addFilter(.blur(radius: 1.2))
        band.fill(Hand.curve([pt(-14, 583), pt(60, 577), pt(130, 582), pt(210, 578), pt(300, 584), pt(414, 576), pt(414, 612), pt(-14, 612)], closed: true),
                  with: .color(p.shade.opacity(0.34)))

        drawFigures(c)
        drawElephant(c)
        drawLedge(c, R)
        drawTree(c, R)

        if scene.night {
            c.fill(Path(all), with: .color(p.veil.opacity(0.6)))
            var starC = c
            starC.clip(to: sky)
            drawStars(starC, R)
        }
        drawSignature(c)
        // the paper's tooth over the paint
        var tooth = c
        tooth.blendMode = scene.night ? .screen : .multiply
        tooth.opacity = scene.night ? 0.2 : 0.28
        let tile = 80 / Double(k)
        let img = Image(decorative: MeltTexture.tooth, scale: 1).interpolation(.medium).resizable()
        var ty = 0.0
        while ty < 612 {
            var tx = -14.0
            while tx < 414 { tooth.draw(img, in: CGRect(x: tx, y: ty, width: tile, height: tile)); tx += tile }
            ty += tile
        }
    }

    /// Blotches of a colour through a region, as watercolour pools on rough paper.
    func mottle(_ c: GraphicsContext, _ region: Path, _ color: Color, _ opacity: Double, seedShift: Double = 0) {
        var cc = c
        cc.clip(to: region)
        let b = region.boundingRect
        cc.clipToLayer(opacity: 1) { m in
            m.draw(Image(decorative: MeltTexture.mottle, scale: 1).resizable(),
                   in: CGRect(x: b.minX - seedShift * 180, y: b.minY - seedShift * 90, width: max(b.width, 300) + 180, height: max(b.height, 300) + 90))
        }
        cc.fill(region, with: .color(color.opacity(opacity)))
    }

    var dayProgress: Double { 1 - scene.share }
    /// The sun's height. The sketch reads the real altitude at the place; the panel has only the day's
    /// share, so this is a fair arc for the season (a noon of about 46°, as New York in October).
    var altitude: Double { 46 * sin(.pi * min(1, max(0, dayProgress))) - 0.5 }
    var sunXY: CGPoint {
        let sx = 196 + 150 * sin((dayProgress - 0.5) * .pi)
        return pt(sx, G.hz(sx) - 330 * sin(max(-6, altitude) * .pi / 180))
    }

    func drawSun(_ c: GraphicsContext) {
        guard let phase = scene.phase else { return }
        if phase == .day {
            let s = sunXY, alt = altitude, r = 15.0
            c.fill(Path(ellipseIn: CGRect(x: s.x - 78, y: s.y - 78, width: 156, height: 156)),
                   with: .radialGradient(Gradient(stops: [.init(color: p.sunHi.opacity(0.75), location: 0), .init(color: p.sun.opacity(0.28), location: 0.35),
                                                          .init(color: p.sun.opacity(0), location: 1)]), center: s, startRadius: 0, endRadius: 78))
            if alt < 12 { dusk(c, at: s.x, opacity: 1 - max(0, alt) / 12, rx: 170, ry: 38) }
            for i in 0..<16 {
                let a = Double(i) / 16 * 2 * .pi + 0.1, r0 = r + 5, r1 = r + 11 + Double(i % 2) * 5
                let pts = (0...4).map { kk -> CGPoint in
                    let rr = r0 + (r1 - r0) * Double(kk) / 4, aa = a + sin(Double(kk) * 1.6 + Double(i)) * 0.05
                    return pt(s.x + cos(aa) * rr, s.y + sin(aa) * rr)
                }
                stroke(c, Hand.curve(Hand.wobble(pts, 0.5, 500 + i, 6)), p.sunLo.opacity(0.8), 1.1)
            }
            c.fill(Hand.curve(Hand.blobPts(s.x + 0.8, s.y + 0.6, r, 61), closed: true),
                   with: .radialGradient(Gradient(stops: [.init(color: p.sunHi, location: 0), .init(color: p.sun, location: 0.7), .init(color: p.sunLo, location: 1)]),
                                         center: pt(s.x - 3, s.y - 3.6), startRadius: 0, endRadius: r * 1.4))
            stroke(c, Hand.curve(Hand.ringPts(s.x, s.y, r, 62, over: 0.14, amp: 0.04)), p.sunLo, 1.2)
        } else {
            // after sunset, a last glow where the sun went down; before sunrise, the first glow where it rises
            let since = (1 - scene.share) * scene.span, until = scene.share * scene.span
            let g1 = max(0, 1 - since / 3000), g2 = max(0, 1 - until / 3000)
            if g1 > 0 { dusk(c, at: 346, opacity: g1, rx: 190, ry: 44) }
            if g2 > 0 { dusk(c, at: 46, opacity: g2, rx: 190, ry: 44) }
        }
    }

    func dusk(_ c: GraphicsContext, at x: Double, opacity: Double, rx: Double, ry: Double) {
        var cc = c
        cc.opacity = opacity
        let y = G.hz(x)
        cc.translateBy(x: x, y: y)
        cc.scaleBy(x: 1, y: ry / rx)
        cc.fill(Path(ellipseIn: CGRect(x: -rx, y: -rx, width: 2 * rx, height: 2 * rx)),
                with: .radialGradient(Gradient(stops: [.init(color: p.sunHi.opacity(0.7), location: 0), .init(color: p.sunLo.opacity(0.25), location: 0.5),
                                                       .init(color: p.sunLo.opacity(0), location: 1)]), center: .zero, startRadius: 0, endRadius: rx))
    }

    func drawGlint(_ c: GraphicsContext) {
        guard scene.phase == .day, altitude < 18 else { return }
        let sx = sunXY.x
        guard sx > 214 else { return }
        for kk in 0..<6 {
            let y = G.hz(sx) + 1.6 + Double(kk) * 1.6, w = 3 + Double(kk) * 2.4
            var path = Path()
            path.move(to: pt(sx - w, y)); path.addLine(to: pt(sx - w + w * 2 * (0.6 + 0.4 * sin(Double(kk) * 2.1 + 1)), y))
            stroke(c, path, p.sunHi.opacity(0.85 - Double(kk) * 0.1), 1)
        }
    }

    /// A sundial on the plain: shadows long and low when the sun is low, falling away from it.
    func drawShadows(_ c: GraphicsContext) {
        guard scene.phase == .day, altitude > 0.3 else { return }
        let alt = altitude
        let Lh = min(5.5, 1 / tan(max(1.2, alt) * .pi / 180)), th = (dayProgress - 0.5) * .pi
        let dx = -sin(th) * Lh, dy = 0.09 * cos(th) * Lh + 0.03
        func pj(_ x: Double, _ y: Double, _ base: Double) -> CGPoint { let h = base - y; return pt(x + dx * h, base + dy * h) }
        var sh = Path()
        sh.addPath(Hand.poly([pt(L.x0, G.ground + 1), pt(L.x1 + L.dx, G.ground - 4), pj(L.x1 + L.dx, L.back, G.ground - 4),
                              pj(L.x0 + 16, L.back, G.ground), pj(L.x0, L.top, G.ground)]))
        var gl: [CGPoint] = [], gr: [CGPoint] = []
        var y = G.yTop - 50
        while y <= G.yBot { gl.append(pj(y < G.yTop ? 128 + (y - G.yTop + 50) * 0.2 : g.xL(y), y + (L.top - G.yBot), G.ground)); y += 8 }
        y = G.yBot
        while y >= G.yTop - 50 { gr.append(pj(y < G.yTop ? 296 - (y - G.yTop + 50) * 0.2 : g.xR(y), y + (L.top - G.yBot), G.ground)); y -= 8 }
        sh.addPath(Hand.poly(gl + gr))
        for (x, yy, h) in [(92.0, G.hz(86) + 13, 15.0), (287, G.hz(274) + 19, 12), (64, 452, 2.5), (362, 470, 3), (176, 428, 2),
                          (G.elephantX - 4, G.hz(G.elephantX) + 7, 46), (G.elephantX + 7, G.hz(G.elephantX) + 7, 42)] {
            sh.addPath(Hand.poly([pt(x - 1.6, yy), pt(x + dx * h, yy + dy * h), pt(x + 1.6, yy + 0.4)]))
        }
        var cc = c
        cc.opacity = min(0.5, 0.22 + alt / 50)
        cc.addFilter(.blur(radius: 0.9))
        let tr = Hand.spline(G.tree, 8).map { pj($0.x, $0.y, G.treeFoot) }
        cc.fill(sh, with: .color(p.shade))
        cc.stroke(Hand.curve(tr), with: .color(p.shade), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        cc.stroke(Hand.curve(Array(tr[Int(Double(tr.count) * 0.55)...])), with: .color(p.shade), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    /// The bell-ringer far out on the plain, at a bell frame, and someone walking towards the sea.
    func drawFigures(_ c: GraphicsContext) {
        let fx = 86.0, fy = G.hz(86) + 13
        var f = Path()
        f.move(to: pt(fx - 6, fy)); f.addLine(to: pt(fx - 6, fy - 15))
        f.move(to: pt(fx + 6, fy)); f.addLine(to: pt(fx + 6, fy - 15))
        f.move(to: pt(fx - 7.5, fy - 15)); f.addLine(to: pt(fx + 7.5, fy - 15))
        f.move(to: pt(fx, fy - 15)); f.addLine(to: pt(fx, fy - 13))
        f.move(to: pt(fx + 1, fy - 9)); f.addLine(to: pt(fx + 9, fy - 6))
        f.move(to: pt(fx + 11, fy)); f.addLine(to: pt(fx + 10, fy - 4))
        f.move(to: pt(fx + 11, fy)); f.addLine(to: pt(fx + 12.4, fy - 4))
        f.move(to: pt(fx + 10.4, fy - 4)); f.addLine(to: pt(fx + 10.4, fy - 8.4))
        f.move(to: pt(fx + 10.4, fy - 7.6)); f.addLine(to: pt(fx + 8.8, fy - 6))
        var bell = Path()
        bell.move(to: pt(fx - 2.6, fy - 9)); bell.addQuadCurve(to: pt(fx + 2.6, fy - 9), control: pt(fx, fy - 19)); bell.closeSubpath()
        c.fill(bell, with: .color(p.sunLo))
        stroke(c, bell, p.line, 0.8)
        stroke(c, f, p.line, 0.8)
        c.fill(Path(ellipseIn: CGRect(x: fx + 9.2, y: fy - 10.8, width: 2.4, height: 2.4)), with: .color(p.line))
        let wx = 274.0, wy = G.hz(274) + 19
        var w = Path()
        w.move(to: pt(wx, wy)); w.addLine(to: pt(wx + 2, wy - 5)); w.addLine(to: pt(wx + 4, wy))
        w.move(to: pt(wx + 2, wy - 5)); w.addLine(to: pt(wx + 2, wy - 10.4))
        w.move(to: pt(wx + 2, wy - 9)); w.addLine(to: pt(wx + 4.6, wy - 6.6))
        w.move(to: pt(wx + 2, wy - 9)); w.addLine(to: pt(wx, wy - 6.4))
        stroke(c, w, p.line, 0.8)
        c.fill(Path(ellipseIn: CGRect(x: wx + 0.6, y: wy - 13.2, width: 2.8, height: 2.8)), with: .color(p.line))
    }

    /// Far out on the plain, an elephant on legs as long as stilts, carrying a bell towards the sunset.
    func drawElephant(_ c: GraphicsContext) {
        let ex = G.elephantX, ef = G.hz(ex) + 7, eY = ef - 40
        for (lx, sp, sd) in [(-9.5, -2.6, 1), (-5, 1.4, 2), (4.5, -1.2, 3), (9.5, 2.6, 4)] {
            let top = pt(ex + lx, eY + 3.5), foot = pt(ex + lx + sp, ef - (sd % 2 == 1 ? 0 : 1.4))
            let knee = pt((top.x + foot.x) / 2 + (sd % 2 == 1 ? 0.9 : -0.9), top.y + (foot.y - top.y) * 0.52)
            stroke(c, Hand.curve(Hand.wobble(Hand.spline([top, knee, foot], 2), 0.3, 700 + sd, 6)), p.beast, sd % 2 == 1 ? 1.1 : 0.9)
            c.fill(Path(ellipseIn: CGRect(x: knee.x - 0.95, y: knee.y - 1.3, width: 1.9, height: 2.6)), with: .color(p.beast))
            c.fill(Path(ellipseIn: CGRect(x: foot.x + 0.5 - 1.5, y: foot.y - 0.7, width: 3, height: 1.4)), with: .color(p.beast))
        }
        let body = Hand.blobPts(ex, eY, 13.5, 707, amp: 0.08).map { pt($0.x, eY + ($0.y - eY) * 0.6) }
        c.fill(Hand.curve(body, closed: true), with: .color(p.beast))
        c.fill(Hand.curve(Hand.blobPts(ex + 13.5, eY - 2.5, 5.4, 709, amp: 0.1), closed: true), with: .color(p.beast))
        stroke(c, Hand.curve(Hand.spline([pt(ex + 17.5, eY - 1), pt(ex + 20, eY + 6), pt(ex + 19.5, eY + 14), pt(ex + 17.6, eY + 16.5), pt(ex + 16.6, eY + 15)], 1.5)), p.beast, 1.5)
        var tusk = Path()
        tusk.move(to: pt(ex + 15.6, eY + 1.2)); tusk.addQuadCurve(to: pt(ex + 20, eY + 1.8), control: pt(ex + 18.2, eY + 3))
        stroke(c, tusk, p.cloud, 0.8)
        c.fill(Hand.curve(Hand.blobPts(ex + 10.2, eY - 1.4, 3.6, 711, amp: 0.14), closed: true), with: .color(p.beast.opacity(0.85)))
        var tail = Path()
        tail.move(to: pt(ex - 13, eY - 0.5)); tail.addQuadCurve(to: pt(ex - 14.6, eY + 6.5), control: pt(ex - 15.2, eY + 2.5))
        stroke(c, tail, p.beast, 0.7)
        // the saddle cloth and the bell frame it carries
        c.fill(Hand.curve(Hand.wobble([pt(ex - 8, eY - 7.6), pt(ex, eY - 8.6), pt(ex + 7.5, eY - 7.8), pt(ex + 7, eY - 1.2), pt(ex, eY - 0.4), pt(ex - 7.6, eY - 1.4)], 0.3, 713, 6), closed: true),
               with: .color(p.rust))
        for kk in 0..<6 {
            let cx = ex - 6.4 + Double(kk) * 2.6, cy = eY - 0.4 + sin(Double(kk)) * 0.4
            c.fill(Path(ellipseIn: CGRect(x: cx - 0.55, y: cy - 0.55, width: 1.1, height: 1.1)), with: .color(p.ochre))
        }
        var frame = Path()
        frame.move(to: pt(ex - 4.6, eY - 8)); frame.addLine(to: pt(ex - 4.3, eY - 20.4))
        frame.move(to: pt(ex + 4.6, eY - 8.4)); frame.addLine(to: pt(ex + 4.4, eY - 20.6))
        frame.move(to: pt(ex - 6, eY - 20.4)); frame.addLine(to: pt(ex + 6, eY - 20.8))
        stroke(c, frame, p.beast, 0.8)
        var bell = Path()
        bell.move(to: pt(ex - 2.6, eY - 13))
        bell.addQuadCurve(to: pt(ex, eY - 18.2), control: pt(ex - 2.4, eY - 18))
        bell.addQuadCurve(to: pt(ex + 2.6, eY - 13), control: pt(ex + 2.4, eY - 18))
        bell.closeSubpath()
        c.fill(bell, with: .color(p.sun))
        stroke(c, bell, p.line, 0.6)
    }

    /// The ledge: a stone block lit on its top, chipped, hatched in its shade, with two drawers.
    func drawLedge(_ c: GraphicsContext, _ R: () -> Double) {
        let topF = [pt(L.x0, L.top), pt(L.x1, L.top), pt(L.x1 + L.dx, L.back), pt(L.x0 + 16, L.back)]
        let front = [pt(L.x0, L.top), pt(L.x1, L.top), pt(L.x1, L.foot), pt(L.x0, L.foot + 1)]
        let side = [pt(L.x1, L.top), pt(L.x1 + L.dx, L.back), pt(L.x1 + L.dx, L.foot - 18), pt(L.x1, L.foot)]
        wash(c, Hand.poly(topF), .color(p.stone3), rim: p.stone2)
        wash(c, Hand.poly(front), .color(p.stone), rim: p.stone2)
        wash(c, Hand.poly(side), .color(p.stone2), rim: p.stone2)
        var hat = Path()
        var x = L.x0 + 8
        while x < L.x1 - 2 {
            if !(x > 126 && x < 296) {
                let y0 = L.top + 40 + R() * 4
                Hand.curve(Hand.wobble([pt(x, y0), pt(x - 5, y0 + 9 + R() * 8)], 0.3, Int(x), 6), into: &hat)
            }
            x += 6
        }
        stroke(c, hat, p.line.opacity(0.34), 0.6)
        var sideHat = Path()
        var y = L.back + 10
        while y < L.foot - 22 { sideHat.move(to: pt(L.x1 + 2, y + 6)); sideHat.addLine(to: pt(L.x1 + L.dx - 2, y)); y += 5 }
        stroke(c, sideHat, p.line.opacity(0.3), 0.55)
        // two drawers let into the stone, as in Dalí's figures; the right one stands a little open
        for (dx0, dy0, w, h, op, sd) in [(132.0, 521.0, 60.0, 13.0, 0.0, 1), (222, 520, 66, 14, 6.5, 2)] {
            let ox = -op * 0.875, oy = op
            if op > 0 {
                c.fill(Hand.poly([pt(dx0, dy0), pt(dx0 + w, dy0), pt(dx0 + w + ox, dy0 + oy), pt(dx0 + ox, dy0 + oy)]), with: .color(p.hollow))
                let ecx = dx0 + w / 2 + ox / 2, ecy = dy0 + oy / 2 + 0.6
                c.fill(Path(ellipseIn: CGRect(x: ecx - w * 0.36, y: ecy - 2.4, width: w * 0.72, height: 4.8)), with: .color(p.sun.opacity(0.9)))
                c.fill(Path(ellipseIn: CGRect(x: ecx - 6 - 3, y: ecy - 0.4 - 1.6, width: 6, height: 3.2)), with: .color(p.sunHi))
                c.fill(Hand.poly([pt(dx0 + w, dy0), pt(dx0 + w + ox, dy0 + oy), pt(dx0 + w + ox, dy0 + h + oy), pt(dx0 + w, dy0 + h)]), with: .color(p.stone2))
                ink(c, [pt(dx0 + w, dy0), pt(dx0 + w, dy0 + h)], w: 0.8, amp: 0.2, seed: 40 + sd, ghost: false)
            }
            let fx0 = dx0 + ox, fy0 = dy0 + oy
            wash(c, Hand.poly([pt(fx0, fy0), pt(fx0 + w, fy0), pt(fx0 + w, fy0 + h), pt(fx0, fy0 + h)]), .color(p.stone3), rim: p.stone2)
            ink(c, Hand.dense([pt(fx0, fy0), pt(fx0 + w, fy0), pt(fx0 + w, fy0 + h), pt(fx0, fy0 + h), pt(fx0, fy0)], 4), w: 1, amp: 0.5, seed: 50 + sd)
            let knob = Path(ellipseIn: CGRect(x: fx0 + w / 2 - 2.1, y: fy0 + h / 2 - 2.1, width: 4.2, height: 4.2))
            c.fill(knob, with: .color(p.bronze)); stroke(c, knob, p.line, 0.7)
        }
        // a folk frieze along its face: setting suns on a horizon line, the Paragonday sign, over and over
        let fry = 509.0
        ink(c, Hand.dense([pt(L.x0 + 6, fry), pt(L.x1 - 6, fry + 1)], 6), w: 1.2, amp: 0.6, seed: 29, ghost: false, color: p.rust)
        var fx = L.x0 + 20, i = 0
        while fx < L.x1 - 12 {
            var arc: [CGPoint] = []
            var a = Double.pi
            while a <= 2 * .pi + 0.01 { arc.append(pt(fx + cos(a) * 6.5, fry + sin(a) * 6.5)); a += .pi / 9 }
            var fill = Hand.curve(Hand.wobble(arc, 0.35, 600 + i, 8))
            fill.closeSubpath()
            c.fill(fill, with: .color(p.ochre.opacity(0.85)))
            stroke(c, Hand.curve(Hand.wobble(arc, 0.35, 620 + i, 8)), p.rust, 1)
            var rays = Path()
            for kk in -1...1 {
                rays.move(to: pt(fx + Double(kk) * 6, fry - 9.5 - (kk != 0 ? 0 : 1.5)))
                rays.addLine(to: pt(fx + Double(kk) * 6 + Double(kk) * 1.4, fry - 9.5 - (kk != 0 ? 0 : 1.5) - 3))
            }
            stroke(c, rays, p.rust, 0.9)
            c.fill(Path(ellipseIn: CGRect(x: fx + 12.5 - 1.1, y: fry + 7 - 1.1, width: 2.2, height: 2.2)), with: .color(p.rust.opacity(0.8)))
            fx += 25; i += 1
        }
        ink(c, Hand.dense([pt(L.x0, L.foot + 1), pt(L.x0, L.top), pt(L.x1, L.top), pt(L.x1, L.foot), pt(L.x0, L.foot + 1)], 5), w: 1.6, amp: 1, seed: 21)
        ink(c, Hand.dense([pt(L.x0, L.top), pt(L.x0 + 16, L.back), pt(L.x1 + L.dx, L.back), pt(L.x1 + L.dx, L.foot - 18), pt(L.x1, L.foot)], 5), w: 1.3, amp: 0.9, seed: 23)
        ink(c, Hand.dense([pt(L.x1, L.top), pt(L.x1 + L.dx, L.back)], 3), w: 1.1, amp: 0.4, seed: 25, ghost: false)
        ink(c, Hand.dense([pt(176, L.top), pt(181, 490), pt(177, 498)], 3), w: 0.8, amp: 0.5, seed: 27, ghost: false)
    }

    /// The dead tree, grown out of the plain, sawn off at the top, its one branch reaching over to the glass.
    func drawTree(_ c: GraphicsContext, _ R: () -> Double) {
        let tp = Hand.spline(G.tree, 5)
        var lft: [CGPoint] = [], rgt: [CGPoint] = []
        for (i, q) in tp.enumerated() {
            let q0 = tp[max(0, i - 1)], q1 = tp[min(tp.count - 1, i + 1)]
            var nx = q0.y - q1.y, ny = q1.x - q0.x
            let l = hypot(nx, ny) == 0 ? 1 : hypot(nx, ny)
            nx /= l; ny /= l
            let w = max(2, 19 - Double(i) * Double(G.tree.count) / Double(tp.count) * 1.05) / 2
            lft.append(pt(q.x + nx * w, q.y + ny * w)); rgt.append(pt(q.x - nx * w, q.y - ny * w))
        }
        let wl = Hand.wobble(lft, 0.9, 41, 20), wr = Hand.wobble(rgt, 0.9, 43, 20)
        wash(c, Hand.curve(wl + wr.reversed(), closed: true), .color(p.bark), rim: p.bark)
        stroke(c, Hand.curve(wl), p.line, 1.2)
        stroke(c, Hand.curve(wr), p.line, 1.2)
        let eb = G.tree[G.elbow]
        let stump = [pt(eb.x - 7, eb.y + 8), pt(eb.x - 6, eb.y - 20), pt(eb.x - 4, eb.y - 33), pt(eb.x + 7, eb.y - 35), pt(eb.x + 9, eb.y - 18), pt(eb.x + 7, eb.y + 4)]
        wash(c, Hand.curve(Hand.spline(stump, 3, closed: true), closed: true), .color(p.bark), rim: p.bark)
        ink(c, Hand.spline(stump, 3), w: 1.2, amp: 0.5, seed: 45, ghost: false)
        let face = CGRect(x: eb.x + 1.5 - 5.8, y: eb.y - 34 - 2.2, width: 11.6, height: 4.4)
        c.fill(Path(ellipseIn: face), with: .color(p.stone3))
        stroke(c, Path(ellipseIn: CGRect(x: eb.x + 1.5 - 3, y: eb.y - 34 - 1.1, width: 6, height: 2.2)), p.line, 0.6)
        ink(c, Hand.ringPts(eb.x + 1.5, eb.y - 34, 5.8, 47, over: 0.1, amp: 0.05).map { pt($0.x, eb.y - 34 + ($0.y - eb.y + 34) * 0.38) },
            w: 0.9, amp: 0.2, seed: 49, ghost: false)
        for tw in [[pt(86, 114), pt(80, 92), pt(72, 74)], [pt(282, 49), pt(290, 34), pt(294, 23)], [pt(32, 336), pt(17, 322), pt(5, 318)],
                   [pt(240, 57), pt(246, 41)], [pt(26, 282), pt(12, 270)], [pt(120, 88), pt(126, 70)]] {
            ink(c, Hand.spline(tw, 3), w: 2.4, amp: 0.5, seed: Int(tw[0].x) + 7, ghost: false)
            ink(c, Hand.spline(tw, 3), w: 1, amp: 0.8, seed: Int(tw[0].x) + 9, ghost: false)
        }
        var marks = Path()
        for _ in 0..<22 {
            let kk = 1 + Int(floor(R() * 44))
            let q = tp[min(tp.count - 2, kk)]
            marks.move(to: pt(q.x - 2, q.y + 4)); marks.addLine(to: pt(q.x - 2 + 0.6 + R(), q.y + 4 - 6 - R() * 6))
        }
        stroke(c, marks, p.paper.opacity(0.3), 0.7)
        c.fill(Path(ellipseIn: CGRect(x: 29 - 2.6, y: 410 - 4.2, width: 5.2, height: 8.4)), with: .color(p.line.opacity(0.8)))
    }

    func drawStars(_ c: GraphicsContext, _ R: () -> Double) {
        for _ in 0..<46 {
            let x = R() * 400, y = 16 + R() * (G.hz(x) - 40), r = 0.6 + R() * 1.6, big = R() > 0.8
            let op = big ? 0.5 + R() * 0.5 : 0.35 + R() * 0.55
            if big {
                c.fill(Hand.poly([pt(x, y - r * 2.2), pt(x + r * 0.45, y - r * 0.45), pt(x + r * 2.2, y), pt(x + r * 0.45, y + r * 0.45),
                                  pt(x, y + r * 2.2), pt(x - r * 0.45, y + r * 0.45), pt(x - r * 2.2, y), pt(x - r * 0.45, y - r * 0.45)]),
                       with: .color(p.starlit.opacity(op)))
            } else {
                let rr = r * 0.55
                c.fill(Path(ellipseIn: CGRect(x: x - rr, y: y - rr, width: 2 * rr, height: 2 * rr)), with: .color(p.starlit.opacity(op)))
            }
        }
    }

    /// The painter's signature: the Paragonday mark, in its teal, with the year.
    func drawSignature(_ c: GraphicsContext) {
        var cc = c
        cc.translateBy(x: 336, y: 558)
        cc.scaleBy(x: 0.115, y: 0.115)
        var m = Hand.curve(Hand.ringPts(128, 124, 53, 5, over: 0.12, amp: 0.04))
        m.addPath(Hand.curve(Hand.wobble(Hand.spline([pt(14, 152), pt(128, 110), pt(244, 146)], 8), 2.2, 6, 60)))
        cc.stroke(m, with: .color(p.mark), style: StrokeStyle(lineWidth: 12, lineCap: .round))
        var t = c
        t.translateBy(x: 369, y: 571)
        t.draw(Text("’26").font(MeltFont.hand(12)).foregroundColor(p.mark), at: .zero, anchor: .bottomLeading)
    }
}

// MARK: - The instrument: the glass, its sand, the soft watch, the crutch, the drip and the bell

private extension MeltDrawing {
    var lobe: MeltGlass.Lobe? { g.lobe() }
    var dripAnchor: (x: Double, y: Double, fall: Double) {
        let lb = lobe
        let x = lb?.tip.x ?? g.xR(G.yBot) - 8, y = lb.map { $0.tip.y - 1.5 } ?? G.yBot + 1
        return (x, y, G.ground + 9 - (y + 13))
    }

    func drawGlassBack(_ c: GraphicsContext) {
        let O = g.outline()
        let d = dripAnchor
        let puddleY = G.ground + 9
        let pud = Hand.blobPts(d.x, puddleY, 10, 311, amp: 0.1).map { pt($0.x, puddleY + ($0.y - puddleY) * 0.26) }
        c.fill(Hand.curve(pud, closed: true), with: .color(p.sun.opacity(0.9)))
        ink(c, pud, w: 0.7, amp: 0.3, seed: 313, closed: true, ghost: false)
        // the ants that found it
        for (x, y, r) in [(190.0, 563.0, 8.0), (203, 561, -4), (216, 562, 10), (229, 559.5, -6), (242, 559, 4), (255, 557.5, -10),
                          (268, 556, 2), (281, 554.5, 8), (294, 553, -4)] where x < d.x - 14 { ant(c, x, y, r) }
        ant(c, d.x - 12, puddleY - 1.5, 30); ant(c, d.x + 13, puddleY - 1, 160); ant(c, d.x + 3, puddleY + 4.5, -80, 0.95)
        // where the glass sits on the stone, a little shadow to seat it
        let sb0 = g.xL(G.yBot), sb1 = lobe != nil ? L.x1 : g.xR(G.yBot)
        let rx = (sb1 - sb0) / 2 + 6
        c.fill(Path(ellipseIn: CGRect(x: (sb0 + sb1) / 2 - rx, y: G.yBot + 3 - 5, width: rx * 2, height: 10)), with: .color(p.shade.opacity(0.28)))
        // the colour misses the line a little, as it does on a hand-painted thing
        c.fill(Hand.curve(O.map { pt($0.x + 2.4, $0.y + 1.6) }, closed: true), with: .color(p.glassTint.opacity(0.75)))
        c.fill(Hand.poly(O), with: .color(p.glassTint))
        if let lb = lobe {
            let poolTop = L.top + lb.lobe * 0.36
            var cc = c
            cc.clip(to: Hand.curve(Hand.spline(lb.knots, 3), closed: true))
            let r = CGRect(x: L.x1 - 12, y: poolTop, width: 90, height: 90)
            cc.fill(Path(r), with: sunGradient(top: r.minY, bottom: r.maxY, alwaysSun: true))
            grain(cc, r, alwaysSun: true)
            stroke(cc, Hand.curve(Hand.wobble(Hand.dense([pt(L.x1 - 4, poolTop + 0.5), pt(L.x1 + 40, poolTop - 0.5)], 4), 0.4, 317, 10)),
                   p.night ? p.starHi : p.sunHi, 1.3)
        }
    }

    func ant(_ c: GraphicsContext, _ x: Double, _ y: Double, _ rot: Double, _ s: Double = 1) {
        var cc = c
        cc.translateBy(x: x, y: y)
        cc.rotate(by: .degrees(rot))
        cc.scaleBy(x: s, y: s)
        var body = Path(ellipseIn: CGRect(x: -3.6, y: -1.05, width: 3, height: 2.1))
        body.addEllipse(in: CGRect(x: -0.85, y: -0.65, width: 1.7, height: 1.3))
        body.addEllipse(in: CGRect(x: 0.8, y: -0.7, width: 1.4, height: 1.4))
        cc.fill(body, with: .color(p.line))
        var legs = Path()
        for (a, b, c2, d) in [(-0.5, 0.0, -1.5, -1.9), (-0.5, 0, -1.5, 1.9), (0, 0, 0.2, -2.1), (0, 0, 0.2, 2.1), (0.4, 0, 1.6, -1.7), (0.4, 0, 1.6, 1.7), (1.9, -0.3, 3.2, -1.2), (1.9, 0.3, 3.2, 1.2)] {
            legs.move(to: pt(a, b)); legs.addLine(to: pt(c2, d))
        }
        cc.stroke(legs, with: .color(p.line), style: StrokeStyle(lineWidth: 0.45, lineCap: .round))
    }

    func sunGradient(top: Double, bottom: Double, alwaysSun: Bool = false) -> GraphicsContext.Shading {
        let stops: [Gradient.Stop] = scene.night && !alwaysSun
            ? [.init(color: p.starHi, location: 0), .init(color: p.star, location: 0.4), .init(color: p.starLo, location: 1)]
            : [.init(color: p.sun, location: 0), .init(color: p.sun, location: 0.3), .init(color: p.sunLo, location: 1)]
        return .linearGradient(Gradient(stops: stops), startPoint: pt(0, top), endPoint: pt(0, bottom))
    }

    /// The sand's grain (by night, its stars), as the sketch's patterns: a few dots to every small tile.
    func grain(_ c: GraphicsContext, _ r: CGRect, alwaysSun: Bool = false) {
        var dark = Path(), lit = Path()
        if scene.night && !alwaysSun {
            var seed: UInt64 = 7
            func rnd() -> Double { seed = (seed * 16807) % 2147483647; return Double(seed) / 2147483647 }
            let stars = (0..<9).map { _ in (rnd() * 30, rnd() * 26, 0.35 + rnd() * 0.75, 0.45 + rnd() * 0.5) }
            var y = floor(r.minY / 26) * 26
            while y < r.maxY {
                var x = floor(r.minX / 30) * 30
                while x < r.maxX {
                    for s in stars { c.fill(Path(ellipseIn: CGRect(x: x + s.0 - s.2, y: y + s.1 - s.2, width: 2 * s.2, height: 2 * s.2)), with: .color(p.starlit.opacity(s.3))) }
                    x += 30
                }
                y += 26
            }
            return
        }
        var y = floor(r.minY / 8) * 8
        while y < r.maxY {
            var x = floor(r.minX / 9) * 9
            while x < r.maxX {
                for (cx, cy, rr) in [(1.6, 1.8, 0.6), (6.1, 3.2, 0.5), (3.4, 6.2, 0.55)] { dark.addEllipse(in: CGRect(x: x + cx - rr, y: y + cy - rr, width: 2 * rr, height: 2 * rr)) }
                for (cx, cy, rr) in [(7.6, 6.6, 0.45), (4.2, 1.0, 0.4)] { lit.addEllipse(in: CGRect(x: x + cx - rr, y: y + cy - rr, width: 2 * rr, height: 2 * rr)) }
                x += 9
            }
            y += 8
        }
        c.fill(dark, with: .color(p.grain))
        c.fill(lit, with: .color(Color.white.opacity(0.42)))
    }

    var levelS: Double { g.levelY(scene.share) }
    var levelE: Double? {
        guard scene.layerKind != .none, scene.layer > 0 else { return nil }
        let yE = g.levelY(scene.share - scene.layer)
        return yE - levelS > 0.5 ? yE : nil
    }
    var dip: Double { scene.flowing ? min(3.5, (G.yNeck - levelS) / 5) : 0 }

    func drawSand(_ c: GraphicsContext) {
        guard scene.phase != nil else { return }
        var cc = c
        var inner = Path()
        var y = G.yTop
        inner.move(to: pt(g.xLi(y), y))
        while y <= G.yNeck + 3 { inner.addLine(to: pt(g.xLi(y), y)); y += 2 }
        y = G.yNeck + 3
        while y >= G.yTop { inner.addLine(to: pt(g.xRi(y), y)); y -= 2 }
        inner.closeSubpath()
        cc.clip(to: inner)
        let yS = levelS, d = dip
        let sand = g.band(yS, G.yNeck + 3, dip: d)
        cc.fill(sand, with: sunGradient(top: yS, bottom: G.yNeck + 3))
        var gc = cc
        gc.clip(to: sand)
        grain(gc, sand.boundingRect)
        var surf: [CGPoint] = []
        var x = g.xLi(yS)
        while x <= g.xRi(yS) {
            let kk = (x - g.xLi(yS)) / max(1, g.xRi(yS) - g.xLi(yS))
            surf.append(pt(x, yS + d * 4 * kk * (1 - kk)))
            x += 4
        }
        if surf.count > 1 { stroke(cc, Hand.curve(Hand.wobble(surf, 0.5, 131, 12)), p.night ? p.starHi : p.sunHi, 1.3) }
        if let yE = levelE {
            let slice = g.layer(yS, yE, dip: d), thin = yE - yS < 14
            let col: Color
            switch scene.layerKind {
            case .rest, .longRest: col = p.paper.opacity(0.5)
            case .preview: col = (scene.night ? p.starlit : p.slice).opacity(0.45)
            case .focus: col = (scene.night ? p.starlit : p.slice).opacity(thin ? 0.95 : 0.62)
            default: col = (scene.night ? p.starlit : p.slice).opacity(thin ? 0.7 : 0.4)
            }
            cc.fill(slice, with: .color(col))
            if scene.layerKind == .focus { stroke(cc, slice, (scene.night ? p.starlit : p.sunHi).opacity(0.3), 4) }
            let ed = yE >= G.yNeck - 1 ? 0 : d
            var edge: [CGPoint] = []
            x = g.xLi(yE)
            while x <= g.xRi(yE) {
                let kk = (x - g.xLi(yE)) / max(1, g.xRi(yE) - g.xLi(yE))
                edge.append(pt(x, yE + ed * 4 * kk * (1 - kk)))
                x += 4
            }
            if edge.count > 1 { stroke(cc, Hand.curve(Hand.wobble(edge, 0.4, 141, 12)), p.line.opacity(0.7), 1.1, dash: [3, 2.6]) }
        }
    }

    /// Where the stream lands: on the topmost finished block, or the bottom of the glass.
    var landY: Double {
        var top = G.yBot - 3
        let (d, sl) = slotLayout
        for i in 0..<min(scene.suns, sl.count) { top = min(top, sl[i].y - MeltGlass.discR(1500, d) - 2) }
        if scene.formingFocus, scene.suns < sl.count { top = min(top, sl[scene.suns].y - MeltGlass.discR(1500, d) - 2) }
        return max(G.yNeck + 8, top)
    }

    /// The stream: bright while a block or break runs; faint while you wait, because the light falls either way.
    func drawStream(_ c: GraphicsContext, phase t: Double) {
        guard scene.share > 0.0005 else { return }
        var path = Path()
        path.move(to: pt(G.CX, G.yNeck - 2)); path.addLine(to: pt(G.CX, landY))
        if scene.flowing {
            stroke(c, path, (scene.night ? p.starlit.opacity(0.22) : p.sunHi.opacity(0.38)), 5)
            stroke(c, path, scene.night ? p.starHi : p.sunLo, 1.9, dash: [1.8, 5.4], phase: CGFloat(-(t.truncatingRemainder(dividingBy: 1.1) / 1.1) * 7.2))
        } else {
            stroke(c, path, p.ink3, 1.1, dash: [1, 8], phase: 0)
        }
    }

    var slotLayout: (Double, [MeltGlass.Slot]) {
        var d = 22.0
        let need = scene.suns + 1
        while g.slots(d).count < need && d > 9 { d -= 2 }
        return (d, g.slots(d))
    }

    /// This day's finished blocks as small suns in the bottom bulb, and the one forming now.
    func drawBottom(_ c: GraphicsContext) {
        let (d, sl) = slotLayout
        let lit = scene.tallyOfLight
        for i in 0..<min(scene.suns, sl.count) {
            let q = sl[i], r = MeltGlass.discR(1500, d), sd = 4000 + i * 31
            c.fill(Hand.curve(Hand.blobPts(q.x + 0.7, q.y + 0.5, r, sd, amp: 0.08), closed: true),
                   with: .radialGradient(Gradient(colors: lit ? [p.sunHi, p.sun] : [p.starHi, p.star]),
                                         center: pt(q.x - r * 0.24, q.y - r * 0.3), startRadius: 0, endRadius: r * 1.4))
            stroke(c, Hand.curve(Hand.ringPts(q.x, q.y, r, sd + 1, over: 0.2, amp: 0.05)), lit ? p.sunLo : p.starLo, 0.9)
        }
        if scene.formingFocus, scene.suns < sl.count {
            let q = sl[scene.suns], r = MeltGlass.discR(1500, d), fr = scene.progress
            stroke(c, Hand.curve(Hand.ringPts(q.x, q.y, r, 171, over: 0.1, amp: 0.04)), scene.night ? p.starHi : p.sunLo, 1, dash: [2, 2])
            let fillC = (scene.night ? p.starHi : p.sun).opacity(0.88)
            if fr >= 0.999 {
                c.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)), with: .color(fillC))
            } else if fr > 0.003 {
                var pie = Path()
                pie.move(to: pt(q.x, q.y)); pie.addLine(to: pt(q.x, q.y - r))
                pie.addRelativeArc(center: pt(q.x, q.y), radius: r, startAngle: .degrees(-90), delta: .degrees(360 * fr))
                pie.closeSubpath()
                c.fill(pie, with: .color(fillC))
            }
        }
        if scene.suns == 0 && !scene.formingFocus && scene.phase != nil {
            for (i, q) in sl.prefix(7).enumerated() {
                stroke(c, Hand.curve(Hand.ringPts(q.x, q.y, MeltGlass.discR(1500, d), 180 + i, over: 0.12, amp: 0.05)), p.ink3, 0.8, dash: [1.2, 2.2])
            }
        }
    }

    /// The scale down the left: hours to the edge of the light, notched into the glass.
    func drawScale(_ ctx: GraphicsContext, _ c: GraphicsContext) {
        guard scene.phase != nil, scene.span > 0 else { return }
        let night = scene.night
        let hy: [Double] = (1..<max(1, Int(ceil(scene.span / 3600)))).filter { Double($0) * 3600 < scene.span }.map { g.levelY(Double($0) * 3600 / scene.span) }
        func usable(_ k: Int) -> Bool {
            let y = hy[k - 1]
            return y - G.yTop >= 44 && y > g.flapLow + 12 && g.xR(y) - g.xL(y) >= 74
        }
        var step = 1
        while step < 4 {
            var ok = true, prevY = G.yNeck - 10
            var kk = step
            while kk <= hy.count {
                if usable(kk) {
                    if prevY - hy[kk - 1] < 22 { ok = false; break }
                    prevY = hy[kk - 1]
                }
                kk += step
            }
            if ok { break }
            step += 1
        }
        for (i, y) in hy.enumerated() {
            let kk = i + 1, x = g.xL(y), major = kk % step == 0 && usable(kk)
            let path = Hand.curve(Hand.wobble([pt(x - (major ? 6 : 3), y + 0.4), pt(x + 1, y), pt(x + (major ? 6 : 3.5), y - 0.3)], 0.35, 150 + kk, 5))
            stroke(c, path, p.line.opacity(major ? 0.8 : 0.38), major ? 1.1 : 0.8)
            if major {
                say(ctx, handText("−\(kk):00", size: 10.5), at: pt(x + 8, y + 4), halo: handText("−\(kk):00", p.halo, size: 10.5))
            }
        }
        // the clock times at the top of the light and at its edge
        let yTopLab = G.yTop + 70
        let xTopLab = min(g.xL(yTopLab - 8), g.xL(yTopLab + 8)) - 5
        if let st = scene.startClock {
            say(ctx, cap(night ? "SUNSET" : "SUNRISE"), at: pt(xTopLab, yTopLab - 4), .end, halo: cap(night ? "SUNSET" : "SUNRISE", p.halo))
            say(ctx, handText(st, size: 11.5), at: pt(xTopLab, yTopLab + 12), .end, halo: handText(st, p.halo, size: 11.5))
        }
        if let ed = scene.edgeClock {
            say(ctx, cap(night ? "SUNRISE" : "SUNSET"), at: pt(G.CX - 22, G.yNeck - 9), .end)
            say(ctx, handText(ed, size: 11.5), at: pt(G.CX - 22, G.yNeck + 9), .end)
        }
    }

    func drawFront(_ c: GraphicsContext) {
        let O = g.outline()
        hatchGlass(c)
        brush(c, O, w: 3, amp: 1.2, seed: 1001, wl: 28, over: 4, vary: 0.55)
        if let lb = lobe {
            ink(c, Hand.spline([pt(L.x1 - 8, L.top - 3), pt(L.x1 + 2, L.top + 1.5), pt(lb.tip.x + 8, L.top + 4)], 3), w: 1, amp: 0.4, seed: 321, ghost: false)
        }
        func wall(_ from: Double, _ to: Double, _ f: (Double) -> Double) -> [CGPoint] {
            var out: [CGPoint] = []; var y = from
            while y <= to { out.append(pt(f(y), y)); y += 6 }
            return out
        }
        let shine = p.starlit
        stroke(c, Hand.curve(Hand.wobble(wall(G.yTop + 24, G.yNeck - 50) { g.xL($0) + 8 }, 0.8, 51, 20)), shine.opacity(0.55), 2.6)
        stroke(c, Hand.curve(Hand.wobble(wall(G.yNeck + 74, G.yBot - 28) { g.xL($0) + 9 }, 0.8, 53, 20)), shine.opacity(0.55 * 0.35), 2.2)
        stroke(c, Hand.curve(Hand.wobble(wall(G.yTop + 42, G.yTop + 78) { g.xR($0) - 7.5 }, 0.5, 55, 12)), shine.opacity(0.55 * 0.4), 1.7)
        if let lb = lobe {
            var s = Path()
            s.move(to: pt(lb.tip.x + 4, L.top + lb.lobe * 0.3))
            s.addQuadCurve(to: pt(lb.tip.x + 3, L.top + lb.lobe * 0.75), control: pt(lb.tip.x + 6.5, L.top + lb.lobe * 0.5))
            stroke(c, s, shine.opacity(0.55 * 0.5), 1.5)
        }
        // the collar at the neck
        let CX = G.CX, yN = G.yNeck
        let col = Hand.spline([pt(CX - 12.5, yN - 4), pt(CX, yN - 7), pt(CX + 12.5, yN - 4), pt(CX + 11.5, yN + 4.5), pt(CX, yN + 6.5), pt(CX - 11.5, yN + 4.5)], 2, closed: true)
        c.fill(Hand.curve(col, closed: true), with: .color(p.bronze))
        ink(c, col, w: 1.3, amp: 0.35, seed: 61, closed: true, ghost: false)
        ink(c, [pt(CX - 11, yN), pt(CX, yN + 1.4), pt(CX + 11, yN)], w: 0.7, amp: 0.2, seed: 63, ghost: false)
        for dx in [-7.0, 7] { c.fill(Path(ellipseIn: CGRect(x: CX + dx - 1, y: yN + 0.8 - 1, width: 2, height: 2)), with: .color(p.line)) }

        drawDial(c)
        drawCrutch(c)
        drawBell(c)
    }

    /// The shaded side of the glass, hatched in short strokes that follow its wall.
    func hatchGlass(_ c: GraphicsContext) {
        let R = Hand.rand(4242)
        var h = Path()
        var y = G.yTop + 30
        while y < G.yBot - 4 {
            if abs(y - G.yNeck) >= 18 {
                let xr = g.xR(y) - 2.6, wid = g.xR(y) - g.xL(y)
                let bulge = y < G.yNeck ? sin(.pi * (G.yNeck - y) / G.HB) : sin(.pi * min(1, (y - G.yNeck) / G.HB2))
                let l = min(wid * 0.26, 4 + 12 * bulge) * (0.65 + 0.55 * R())
                Hand.hatch(xr, y, -l * 0.84, l * 0.5, (R() - 0.5) * 0.2, into: &h)
                if y > G.yNeck + G.HB2 * 0.5 && R() > 0.3 { Hand.hatch(xr - 1.2, y + 2.5, -l * 0.66, -l * 0.42, (R() - 0.5) * 0.2, into: &h) }
            }
            y += 3.6 + R() * 1.8
        }
        y = G.yNeck + 70
        while y < G.yBot - 8 {
            let l = 4 + R() * 4
            Hand.hatch(g.xL(y) + 2.4, y, l * 0.8, l * 0.5, (R() - 0.5) * 0.2, into: &h)
            y += 5 + R() * 2
        }
        stroke(c, h, p.line.opacity(0.42), 0.7)
    }

    /// The soft watch the glass hangs from, thrown over the branch, its left side running like warm wax.
    func drawDial(_ c: GraphicsContext) {
        let outer = g.dialRing(1), face = g.dialRing(0.88)
        let cx = g.dialCenter.x
        c.fill(Hand.curve(outer.map { pt($0.x + 3, $0.y + 8) }, closed: true), with: .color(p.shade.opacity(0.16)))
        let ob = Hand.curve(outer, closed: true)
        c.fill(ob, with: .linearGradient(Gradient(colors: [p.brassHi, p.bronze]), startPoint: pt(0, ob.boundingRect.minY), endPoint: pt(0, ob.boundingRect.maxY)))
        c.fill(Hand.curve(face, closed: true), with: .linearGradient(Gradient(stops: [.init(color: p.dial, location: 0), .init(color: p.dial, location: 0.55), .init(color: p.dial2, location: 1)]),
                                                                    startPoint: pt(0, 56), endPoint: pt(0, 190)))
        // where it folds back over the branch, the back of the case shows, hatched
        let cr: [CGPoint] = stride(from: cx - 96, through: cx + 96, by: 3).map { pt($0, G.branchY($0) + 1.5) }
        var fc = c
        fc.clip(to: ob)
        fc.fill(Hand.poly([pt(cx - 100, 0), pt(cx + 100, 0)] + cr.reversed()), with: .color(p.bronze))
        let RF = Hand.rand(811)
        var fold = Path()
        var x = cx - 90
        while x < cx + 92 { Hand.hatch(x, G.branchY(x) - 0.5, -2.5, -5 - RF() * 3, 0.08, into: &fold); x += 3.2 }
        stroke(fc, fold, p.line.opacity(0.55), 0.6)
        ink(fc, cr, w: 1.1, amp: 0.5, seed: 813, ghost: false)
        // the face's own shading, where the flap and the sag catch the shade
        let RH = Hand.rand(817)
        var hh = Path()
        for i in 0..<26 {
            let u = -0.98 + Double(i) * 0.028, vv = 0.1 + RH() * 0.6
            if u * u + vv * vv > 0.74 { continue }
            let q = g.dialAt(u, vv)
            Hand.hatch(q.x, q.y, 3.4 + RH() * 2, 4 + RH() * 3, 0.1, into: &hh)
        }
        stroke(c, hh, p.line.opacity(0.35), 0.55)
        // the minutes and the hours
        var minor = Path(), major = Path()
        for i in 0..<60 {
            let a = Double(i) / 60 * 2 * .pi, hr = i % 5 == 0
            let a0 = MeltGlass.polar(hr ? 0.75 : 0.815, a), a1 = MeltGlass.polar(0.855, a)
            let q0 = g.dialAt(a0.0, a0.1), q1 = g.dialAt(a1.0, a1.1)
            if hr { major.move(to: q0); major.addLine(to: q1) } else { minor.move(to: q0); minor.addLine(to: q1) }
        }
        stroke(c, major, p.dialInk, 1.15)
        stroke(c, minor, p.dialInk.opacity(0.55), 0.5)
        for kk in 1...11 {
            let uv = MeltGlass.polar(0.6, -Double(kk) * 2 * .pi / 12)
            dialText(c, uv.0, uv.1, "−\(kk)", Text("−\(kk)").font(MeltFont.display(kk >= 10 ? 13.5 : 15, .semibold)).foregroundColor(p.dialInk))
        }
        // at the top, where the count runs out, the sun sits on its horizon
        let sunPts: [CGPoint] = (0...12).map { i in
            let a = Double.pi + Double(i) / 12 * .pi
            return g.dialAt(0.105 * cos(a), -0.585 + 0.105 * sin(a) * 1.5)
        }
        var sp = Hand.curve(sunPts)
        sp.closeSubpath()
        c.fill(sp, with: .color(p.sun))
        ink(c, sunPts, w: 0.8, amp: 0.15, seed: 819, ghost: false, color: p.dialInk)
        ink(c, [g.dialAt(-0.2, -0.58), g.dialAt(0, -0.6), g.dialAt(0.2, -0.58)], w: 1.1, amp: 0.2, seed: 821, ghost: false, color: p.dialInk)
        // the maker's name where a watchmaker signs: the Paragonday mark, in its teal
        let mk: [CGPoint] = (0...40).map { i in let a = Double(i) / 40 * 2 * .pi + 0.3; return g.dialAt(0.11 * cos(a), 0.3 + 0.11 * sin(a)) }
        var markP = Hand.curve(Hand.wobble(mk, 0.2, 823, 8))
        markP.addPath(Hand.curve(Hand.wobble(Hand.spline([g.dialAt(-0.22, 0.36), g.dialAt(0, 0.28), g.dialAt(0.22, 0.35)], 2), 0.2, 825, 8)))
        stroke(c, markP, p.mark, 1.4)
        dialText(c, 0, 0.5, "PARAGONDAY", Text("PARAGONDAY").font(MeltFont.type(6.5)).tracking(0.8).foregroundColor(p.dialInk.opacity(0.7)))
        // the case, inked twice, and the face's edge
        brush(c, outer, w: 2.2, amp: 0.7, seed: 827, closed: true)
        ink(c, face, w: 0.7, amp: 0.25, seed: 829, closed: true, ghost: false)
        // the winding crown, on the right, still crisp
        let cw = g.dialAt(1.02, -0.05), cw2 = g.dialAt(1.12, -0.05)
        var crown = Path()
        crown.move(to: cw); crown.addLine(to: cw2)
        stroke(c, crown, p.bronze, 5)
        ink(c, [cw, cw2], w: 0.9, amp: 0.1, seed: 831, ghost: false)
        // a fly, as on the watch in the painting
        let fp = g.dialAt(0.42, 0.2)
        var fly = c
        fly.translateBy(x: fp.x, y: fp.y)
        fly.rotate(by: .degrees(-28))
        fly.fill(Path(ellipseIn: CGRect(x: -2.6, y: -1.3, width: 5.2, height: 2.6)), with: .color(p.line))
        fly.fill(Path(ellipseIn: CGRect(x: 1.6, y: -1, width: 2, height: 2)), with: .color(p.line))
        var wings = Path()
        wings.move(to: pt(-0.6, -0.4)); wings.addCurve(to: pt(-4.8, -1.8), control1: pt(-2.2, -3.8), control2: pt(-5.2, -4))
        wings.addCurve(to: pt(-0.6, -0.4), control1: pt(-4.4, -0.6), control2: pt(-2.2, -0.4))
        wings.move(to: pt(-0.6, 0.4)); wings.addCurve(to: pt(-4.8, 1.8), control1: pt(-2.2, 3.8), control2: pt(-5.2, 4))
        wings.addCurve(to: pt(-0.6, 0.4), control1: pt(-4.4, 0.6), control2: pt(-2.2, 0.4))
        fly.fill(wings, with: .color(p.starlit.opacity(0.55)))
        fly.stroke(wings, with: .color(p.line), lineWidth: 0.45)
        var legs = Path()
        for (a, b, c2, d) in [(0.4, 1.0, 1.0, 3.2), (1.4, 1, 2.6, 3), (0.4, -1, 1, -3.2), (1.4, -1, 2.6, -3)] { legs.move(to: pt(a, b)); legs.addLine(to: pt(c2, d)) }
        fly.stroke(legs, with: .color(p.line), lineWidth: 0.4)
        // the drop gathering at the tip of the flap (it swells and falls in the motion layer)
    }

    /// A word painted on the face, carried by the face as it bends (the warp's local stretch as a matrix).
    func dialText(_ c: GraphicsContext, _ u: Double, _ vv: Double, _ key: String, _ text: Text) {
        let e = 0.01, q = g.dialAt(u, vv), pu = g.dialAt(u + e, vv), pv = g.dialAt(u, vv + e), kk = e * MeltGlass.dialRX
        var cc = c
        cc.concatenate(CGAffineTransform(a: (pu.x - q.x) / kk, b: (pu.y - q.y) / kk, c: (pv.x - q.x) / kk, d: (pv.y - q.y) / kk, tx: q.x, ty: q.y))
        cc.draw(text, at: .zero, anchor: .center)
    }

    /// The hand, which stands at the tilset now (by night, the tilrise).
    func drawHand(_ c: GraphicsContext) {
        guard scene.phase != nil else { return }
        let left = scene.share * scene.span
        let a = -((left / 3600).truncatingRemainder(dividingBy: 12)) * 2 * .pi / 12
        let d = MeltGlass.polar(1, a), n = (cos(a), sin(a))
        func at(_ r: Double, _ w: Double) -> CGPoint { g.dialAt(d.0 * r + n.0 * w, d.1 * r + n.1 * w) }
        let shape = [at(-0.15, 0), at(-0.07, 0.042), at(0.06, 0.036), at(0.34, 0.016), at(0.42, 0.05), at(0.52, 0),
                     at(0.42, -0.05), at(0.34, -0.016), at(0.06, -0.036), at(-0.07, -0.042)]
        c.fill(Hand.curve(shape.map { pt($0.x + 1.6, $0.y + 2.4) }, closed: true), with: .color(p.shade.opacity(0.22)))
        c.fill(Hand.poly(shape), with: .color(p.line))
        let o = g.dialAt(0, 0)
        let hub = Path(ellipseIn: CGRect(x: o.x - 2.6, y: o.y - 2.6, width: 5.2, height: 5.2))
        c.fill(hub, with: .color(p.bronze))
        c.stroke(hub, with: .color(p.line), lineWidth: 0.8)
    }

    /// The crutch, propping the slumped bulb from the plain.
    func drawCrutch(_ c: GraphicsContext) {
        let ty = 402.0, tx = g.xL(ty) - 3, fx = 82.0, fyy = 562.0
        let ang = atan2(fyy - ty, fx - tx), nx = -sin(ang), ny = cos(ang)
        let forkY = ty + 46, forkX = tx + (fx - tx) * (forkY - ty) / (fyy - ty)
        let pad = Hand.spline([pt(tx + nx * 15 + 2, ty + ny * 15 - 2), pt(tx + 3, ty + 1), pt(tx - nx * 15 + 2, ty - ny * 15 + 1)], 3)
        c.fill(Hand.poly([pt(forkX - 2.2, forkY), pt(fx - 2.2, fyy), pt(fx + 2.2, fyy), pt(forkX + 2.2, forkY)]), with: .color(p.stick))
        ink(c, Hand.dense([pt(forkX - 2, forkY), pt(fx - 2, fyy)], 4), w: 1.3, amp: 0.5, seed: 91)
        ink(c, Hand.dense([pt(forkX + 2, forkY), pt(fx + 2, fyy)], 4), w: 1.3, amp: 0.5, seed: 93)
        for (sgn, sd) in [(1.0, 95), (-1, 97)] {
            let prong = Hand.spline([pt(forkX, forkY), pt(forkX + sgn * nx * 8 - 2, forkY - 18), sgn > 0 ? pad[0] : pad[pad.count - 1]], 3)
            stroke(c, Hand.curve(prong), p.stick, 3.4)
            ink(c, prong, w: 1.1, amp: 0.4, seed: sd, ghost: false)
        }
        c.fill(Hand.curve(pad + pad.reversed().map { pt($0.x - 4 * cos(ang), $0.y - 4 * sin(ang)) }, closed: true), with: .color(p.stick2))
        ink(c, pad, w: 1.6, amp: 0.4, seed: 99)
        var wrap = Path()
        for dy in [3.0, 6.5, 10] { wrap.move(to: pt(forkX - 3.5, forkY + dy)); wrap.addLine(to: pt(forkX + 3.5, forkY + dy - 1.6)) }
        stroke(c, wrap, p.wood2, 1.1)
        ink(c, [pt(fx - 5, fyy + 0.5), pt(fx + 5, fyy)], w: 1.2, amp: 0.2, seed: 101, ghost: false)
    }

    /// The bell on the end of the branch, rung when a block ends.
    func drawBell(_ c: GraphicsContext) {
        let bt = G.tree[G.tree.count - 1], bxx = bt.x + 2, byy = bt.y + 31
        stroke(c, Hand.curve(Hand.wobble(Hand.dense([bt, pt(bxx, byy - 12)], 3), 0.5, 111, 10)), p.line, 0.9)
        var bell = Hand.relative(from: pt(bxx - 2, byy - 12), [(-4.6, 1, -5.4, 6, -5.8, 9.6), (-0.3, 2.4, -2.2, 3.6, -2.8, 4.6)])
        bell.addLine(to: pt(bxx - 2 - 5.8 - 2.8 + 17.2, byy - 12 + 9.6 + 4.6))
        let start = pt(bxx - 2 - 5.8 - 2.8 + 17.2, byy - 12 + 14.2)
        bell.addCurve(to: pt(start.x - 2.8, start.y - 4.6), control1: pt(start.x - 0.6, start.y - 1), control2: pt(start.x - 2.5, start.y - 2.2))
        let s2 = pt(start.x - 2.8, start.y - 4.6)
        bell.addCurve(to: pt(s2.x - 5.8, s2.y - 9.6), control1: pt(s2.x - 0.4, s2.y - 3.6), control2: pt(s2.x - 1.2, s2.y - 8.6))
        bell.closeSubpath()
        c.fill(bell, with: .color(p.bronze))
        stroke(c, bell, p.line, 1.3)
        c.fill(Path(ellipseIn: CGRect(x: bxx - 1.6, y: byy + 3.6 - 1.6, width: 3.2, height: 3.2)), with: .color(p.line))
        var shine = Path()
        shine.move(to: pt(bxx - 4.5, byy - 3)); shine.addQuadCurve(to: pt(bxx - 1.9, byy - 9), control: pt(bxx - 3.9, byy - 7))
        stroke(c, shine, p.starlit.opacity(0.55), 1)
    }

    /// The drip of light swelling at the lowest point of the glass, then falling to the plain; and the
    /// brass drop at the watch's flap. `time` nil is the still frame Reduce Motion asks for.
    func drawDrip(_ c: GraphicsContext, time: Double?) {
        func drop(_ c: GraphicsContext, at x: Double, _ y: Double, r: Double, phase: Double?, fall: Double, fill: GraphicsContext.Shading, period: Double) {
            // the sketch's keyframes: swell, stretch, fall and splash, then gather again
            var sx = 0.8, sy = 0.75, ty = 0.0, op = 1.0
            if let t = phase {
                let f = (t.truncatingRemainder(dividingBy: period)) / period
                func ease(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * (u * u * (3 - 2 * u)) }
                switch f {
                case ..<0.60: let u = f / 0.6; sx = ease(0.3, 1, u); sy = ease(0.25, 1.08, u)
                case ..<0.68: let u = (f - 0.6) / 0.08; sx = ease(1, 0.88, u); sy = ease(1.08, 1.5, u)
                case ..<0.73: let u = (f - 0.68) / 0.05; sx = ease(0.88, 0.7, u); sy = ease(1.5, 1.3, u); ty = fall * u * u; op = 1 - 0.05 * u
                case ..<0.75: let u = (f - 0.73) / 0.02; sx = ease(0.7, 1.6, u); sy = ease(1.3, 0.25, u); ty = fall; op = 0.95 * (1 - u)
                case ..<0.76: op = 0
                default: let u = (f - 0.76) / 0.24; sx = ease(0.1, 0.3, u); sy = ease(0.1, 0.25, u)
                }
            }
            guard op > 0.01 else { return }
            let s = r / 5
            var shape = Hand.relative(from: .zero, [(2.8 * s, 4 * s, 5 * s, 7.6 * s, 5 * s, 10.6 * s)])
            shape.addRelativeArc(center: pt(0, 10.6 * s), radius: 5 * s, startAngle: .degrees(0), delta: .degrees(180))
            shape.addCurve(to: .zero, control1: pt(-5 * s, 7.6 * s), control2: pt(-2.8 * s, 4 * s))
            shape.closeSubpath()
            var cc = c
            cc.opacity = op
            cc.translateBy(x: x, y: y + ty)
            cc.scaleBy(x: sx, y: sy)
            cc.fill(shape, with: fill)
            cc.stroke(shape, with: .color(p.line), lineWidth: 0.9 / max(0.3, sy))
        }
        let d = dripAnchor
        drop(c, at: d.x, d.y, r: 5, phase: time, fall: d.fall,
             fill: .radialGradient(Gradient(colors: [p.sunHi, p.sunLo]), center: pt(-1.5, 9), startRadius: 0, endRadius: 7), period: 11)
        var tip = g.dialRing(1)[0]
        for q in g.dialRing(1) where q.y > tip.y { tip = q }
        drop(c, at: tip.x, tip.y - 3, r: 3.6, phase: time.map { $0 + 5 }, fall: 34,
             fill: .linearGradient(Gradient(colors: [p.brassHi, p.bronze]), startPoint: pt(0, 0), endPoint: pt(0, 14)), period: 13)
    }

    // MARK: words beside the glass: paper tags tied on, and a few notes in the hand

    func drawLabels(_ ctx: GraphicsContext, _ c: GraphicsContext) {
        guard scene.phase != nil else { return }
        let night = scene.night
        let yS = levelS
        struct Item { var a: Double; var ax: Double?; var lines: [Text]; var seed: Int; var h: Double = 0; var top: Double = 0 }
        var items: [Item] = [Item(a: yS, ax: nil, lines: [cap(night ? "NIGHT LEFT" : "LIGHT LEFT", p.tagInk3, size: 6.8),
                                                           handText(scene.leftText, p.goldInk, size: 12.5)], seed: 201)]
        if let yE = levelE, let txt = scene.layerText {
            let bxr = max(g.xR(yS), g.xR(yE), g.xR((yS + yE) / 2)) + 5
            stroke(c, Hand.curve(Hand.wobble([pt(bxr - 5, yS), pt(bxr, yS + 1), pt(bxr, (yS + yE) / 2), pt(bxr, yE - 1), pt(bxr - 5, yE)], 0.5, 191, 10)),
                   night ? p.star : p.sunLo, 1.8)
            let what: String
            switch scene.layerKind {
            case .preview: what = "NEXT BLOCK"
            case .rest: what = "BREAK"
            case .longRest: what = "LONG BREAK"
            case .focus: what = "THIS BLOCK"
            default: what = "PAUSED"
            }
            var lines = [cap(what, p.tagInk3, size: 6.8), handText(txt, p.tagInk, size: 12.5)]
            if scene.layerWarn { lines.append(cap(night ? "ENDS PAST SUNRISE" : "ENDS PAST SUNSET", meltRGB(0xA3402F), size: 6.2)) }
            items.append(Item(a: (yS + yE) / 2, ax: bxr, lines: lines, seed: 211))
        }
        // heights in scene units: each line's height in points, over the scale
        func lineH(_ i: Int) -> Double { (i == 1 ? 15.5 : 10.5) / Double(k) }
        for i in items.indices { items[i].h = (7 / Double(k)) + items[i].lines.indices.reduce(0) { $0 + lineH($1) } }
        items.sort { $0.a < $1.a }
        var prev = -1e9
        for i in items.indices { items[i].top = max(items[i].a - items[i].h / 2, prev + 6, G.yTop + 8); prev = items[i].top + items[i].h }
        let maxBottom = G.yNeck + 70
        for i in items.indices.reversed() {
            let lim = i == items.count - 1 ? maxBottom : items[i + 1].top - 6
            if items[i].top + items[i].h > lim { items[i].top = lim - items[i].h }
        }
        for it in items {
            let wPt = it.lines.map { width(ctx, $0) }.max() ?? 30
            let w = (Double(wPt) + 18) / Double(k)
            let wallMax = max(g.xR(it.top), g.xR(it.top + it.h), g.xR(it.top + it.h / 2))
            let x = min(wallMax + 14, 396 - w)
            tag(ctx, c, anchor: pt(it.ax ?? g.xR(it.a) - 1, it.a), x: x, y: it.top, w: w, h: it.h, lines: it.lines, seed: it.seed, lineH: lineH)
        }
        // since sunrise, high on the right
        let passedSec = (1 - scene.share) * scene.span
        if yS - G.yTop > 70, passedSec > 20 * 60, let pt0 = scene.passedText {
            let yy = max(G.yTop + 40, min((G.yTop + yS) / 2, (items.first?.top ?? yS) - 24))
            let xx = min(g.xR(yy) + 12, 330)
            say(ctx, cap(night ? "SINCE SUNSET" : "SINCE SUNRISE"), at: pt(xx, yy - 3))
            say(ctx, handText(pt0, p.line.opacity(0.82)), at: pt(xx, yy + 13))
        }
        // the blocks below
        if scene.suns > 0, let tt = scene.tallyText {
            let y = G.yNeck + 54
            var x = 1e9
            var yy = y - 16
            while yy <= y + 44 { x = min(x, g.xL(yy) - 9); yy += 4 }
            say(ctx, cap("BLOCKS"), at: pt(x, y - 16), .end)
            say(ctx, handText("\(scene.suns)", size: 21), at: pt(x, y + 8), .end)
            say(ctx, handText(tt, size: 11.5), at: pt(x, y + 26), .end)
            say(ctx, cap(scene.tallyOfLight ? "OF LIGHT" : "OF NIGHT"), at: pt(x, y + 38), .end)
        } else if !scene.formingFocus {
            let gx = g.bx(0.62)
            say(ctx, handText("finished blocks", p.ink3, size: 11.5), at: pt(gx, G.yNeck + 96), .middle)
            say(ctx, handText("collect here", p.ink3, size: 11.5), at: pt(gx, G.yNeck + 114), .middle)
        }
    }

    /// A paper tag tied to the glass with a bit of string.
    func tag(_ ctx: GraphicsContext, _ c: GraphicsContext, anchor a: CGPoint, x: Double, y: Double, w: Double, h: Double,
             lines: [Text], seed: Int, lineH: (Int) -> Double) {
        let R = Hand.rand(seed), rot = (R() - 0.5) * 5
        let box = [pt(x, y + 4), pt(x + 4, y), pt(x + w - 3, y + 0.5), pt(x + w, y + 3.5), pt(x + w + 0.5, y + h - 3),
                   pt(x + w - 3.5, y + h), pt(x + 3, y + h - 0.4), pt(x - 0.4, y + h - 4)]
        let hx = x + 6.5, hy = y + h / 2
        let sag = max(a.y, hy) + 5 + abs(hx - a.x) * 0.06
        stroke(c, Hand.curve(Hand.wobble(Hand.spline([a, pt((a.x + hx) / 2, sag), pt(hx, hy)], 3), 0.4, seed + 5, 10)), p.line.opacity(0.75), 0.8)
        var tc = c
        tc.translateBy(x: hx, y: hy); tc.rotate(by: .degrees(rot)); tc.translateBy(x: -hx, y: -hy)
        let boxP = Hand.curve(Hand.wobble(Hand.dense(box, 3, closed: true), 0.5, seed + 9, 14), closed: true)
        tc.fill(boxP, with: .color(p.tag))
        tc.stroke(boxP, with: .color(p.tagInk), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        let hole = Path(ellipseIn: CGRect(x: hx - 2.2, y: hy - 2.2, width: 4.4, height: 4.4))
        tc.fill(hole, with: .color(p.paper))
        tc.stroke(hole, with: .color(p.tagInk), lineWidth: 0.8)
        // the words, turned with the tag
        var wc = ctx
        let hv = v(pt(hx, hy))
        wc.translateBy(x: hv.x, y: hv.y); wc.rotate(by: .degrees(rot)); wc.translateBy(x: -hv.x, y: -hv.y)
        var yy = y + 3.5 / Double(k)
        for (i, t) in lines.enumerated() {
            yy += lineH(i)
            say(wc, t, at: pt(x + 12, yy - (i == 1 ? 3.2 : 1.6) / Double(k)))
        }
    }
}
