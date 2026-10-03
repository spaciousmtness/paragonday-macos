import SwiftUI

// The Light Glass hourglass: the top bulb holds what is left of today's light (at night, of the night
// until sunrise), the block's minutes are the layer that pours through the neck, and each finished
// block lies in the bottom bulb as a small sun. Draws a LightGlass.Snapshot and nothing else, so the
// popover and the PNG render harness show exactly the same picture.

struct LightGlassActions {
    var start: (LightGlass.Preset) -> Void = { _ in }
    var custom: () -> Void = {}
    var pauseResume: () -> Void = {}
    var stop: () -> Void = {}
    var acceptOffer: () -> Void = {}
    var editLabel: () -> Void = {}
}

/// Live wrapper for the popover: the controller swaps in a new snapshot every second.
final class LightGlassModel: ObservableObject {
    @Published var snapshot: LightGlass.Snapshot
    init(_ snapshot: LightGlass.Snapshot) { self.snapshot = snapshot }
}

struct LightGlassPanel: View {
    @ObservedObject var model: LightGlassModel
    let actions: LightGlassActions
    var body: some View { LightGlassView(snap: model.snapshot, actions: actions) }
}

// MARK: - Palette

struct LightGlassPalette {
    var background: [Color]
    var ink: Color
    var soft: Color
    var glassLine: Color
    var glassFill: Color
    var frame: Color
    var sand: [Color]
    var band: Color
    var mark: Color
    var spent: [Color]
    var stream: Color
    var warn: Color
    var button: Color
    var buttonText: Color
    var starlit: Bool

    static let day = LightGlassPalette(
        background: [rgb(0xFFFBF3), rgb(0xFAEFD9)],
        ink: rgb(0x221C15), soft: rgb(0x7D7062),
        glassLine: rgb(0x4A3B2C, 0.35), glassFill: Color.white.opacity(0.45), frame: rgb(0x4A3426, 0.85),
        sand: [rgb(0xF8C760), rgb(0xEC9640)], band: rgb(0xFFE9A6), mark: rgb(0xA4561B),
        spent: [rgb(0xEBCF9F), rgb(0xD9A766)], stream: rgb(0xF0A93F), warn: rgb(0xB8501A),
        button: rgb(0x221C15), buttonText: rgb(0xFFFBF3), starlit: false)

    static let night = LightGlassPalette(
        background: [rgb(0x0D1330), rgb(0x1B2452)],
        ink: rgb(0xEEF0FF), soft: rgb(0x9BA4CB),
        glassLine: rgb(0xC8D2FF, 0.38), glassFill: Color.white.opacity(0.05), frame: rgb(0xB7C1EE, 0.55),
        sand: [rgb(0x6474C2), rgb(0x2F3B7E)], band: rgb(0x9DAEF2), mark: rgb(0xDCE3FF),
        spent: [rgb(0x2A3468), rgb(0x1F2754)], stream: rgb(0xA9B8FF), warn: rgb(0xF4B56E),
        button: rgb(0xEEF0FF), buttonText: rgb(0x111735), starlit: true)
}

private func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
    Color(.sRGB,
          red: Double((hex >> 16) & 0xFF) / 255,
          green: Double((hex >> 8) & 0xFF) / 255,
          blue: Double(hex & 0xFF) / 255,
          opacity: alpha)
}

// MARK: - Panel

struct LightGlassView: View {
    let snap: LightGlass.Snapshot
    var actions: LightGlassActions?

    private var p: LightGlassPalette { snap.phase == .night ? .night : .day }
    private var active: Bool { snap.mode != .idle }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("LIGHT GLASS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.2)
                    .foregroundColor(p.soft)
                Spacer()
                Text(snap.horizonNow)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(p.ink)
            }

            HourglassCanvas(snap: snap, palette: p)
                .frame(height: 250)
                .padding(.top, 10)

            readout
                .padding(.top, 10)

            if snap.pomodorosInCycle > 0 || snap.title == "Pomodoro" {
                HStack(spacing: 6) {
                    ForEach(0..<LightGlass.pomodorosPerLongBreak, id: \.self) { i in
                        Circle()
                            .fill(i < snap.pomodorosInCycle ? p.stream : p.soft.opacity(0.25))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 8)
            }

            Rectangle().fill(p.soft.opacity(0.22)).frame(height: 1).padding(.top, 14)

            HStack {
                Text(snap.todayLine)
                    .font(.system(size: 11.5))
                    .foregroundColor(p.soft)
                Spacer()
            }
            .padding(.top, 8)

            if let actions = actions {
                controls(actions)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 300)
        .background(LinearGradient(colors: p.background, startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder private var readout: some View {
        VStack(spacing: 3) {
            if active {
                Text(snap.label.isEmpty ? snap.title : snap.label)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundColor(p.ink)
                    .lineLimit(1)
                Text(snap.remainingText)
                    .font(.system(size: 42, weight: .light, design: .serif).monospacedDigit())
                    .foregroundColor(p.ink)
                if snap.mode == .paused {
                    Text("Paused · the light keeps falling")
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundColor(p.soft)
                }
                if let ends = snap.endsAtText {
                    Text(snap.label.isEmpty ? ends : "\(snap.title) · \(ends)")
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundColor(p.soft)
                }
                if let warning = snap.warning {
                    Text(warning)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(p.warn)
                        .padding(.top, 2)
                }
            } else {
                Text(snap.leftText)
                    .font(.system(size: 21, weight: .light, design: .serif).monospacedDigit())
                    .foregroundColor(p.ink)
                if let note = snap.note {
                    Text(note)
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundColor(p.soft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(snap.label.isEmpty ? "What's next?" : "Next: \(snap.label)")
                        .font(.system(size: 12, design: .serif).italic())
                        .foregroundColor(p.soft)
                        .lineLimit(1)
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func controls(_ a: LightGlassActions) -> some View {
        VStack(spacing: 8) {
            switch snap.mode {
            case .running, .paused:
                HStack(spacing: 8) {
                    pill(snap.mode == .paused ? "Resume" : "Pause", primary: true, action: a.pauseResume)
                    pill(snap.isRest ? "End break" : "Stop", action: a.stop)
                    if !snap.isRest { pill("What's next?", action: a.editLabel) }
                }
            case .idle:
                if let offer = snap.offerTitle {
                    HStack(spacing: 8) {
                        pill(offer, primary: true, action: a.acceptOffer)
                        if offer.hasSuffix("break") { pill("Skip break", action: a.stop) }
                    }
                }
                HStack(spacing: 6) {
                    pill("Pomodoro", primary: snap.offerTitle == nil) { a.start(.pomodoro) }
                    pill("50") { a.start(.focus50) }
                    pill("90") { a.start(.deep90) }
                    pill(snap.phase == .night ? "Until sunrise" : "Until sunset") { a.start(.untilSunset) }
                }
                HStack(spacing: 6) {
                    pill("Custom…", action: a.custom)
                    pill(snap.label.isEmpty ? "What's next?" : "Change what's next", action: a.editLabel)
                }
            }
        }
    }

    private func pill(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundColor(primary ? p.buttonText : p.ink)
                .background(Capsule().fill(primary ? p.button : p.ink.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The glass

struct HourglassCanvas: View {
    let snap: LightGlass.Snapshot
    let palette: LightGlassPalette

    var body: some View {
        Canvas { ctx, size in
            HourglassDrawing(snap: snap, p: palette, size: size).draw(in: &ctx)
        }
    }
}

/// The glass's shape and the sand levels, kept apart from the drawing so the maths reads plainly.
struct HourglassGeometry {
    let cx: CGFloat
    let yTop: CGFloat       // top cap's inner edge, where the top bulb starts
    let yBottom: CGFloat    // bottom cap's inner edge
    let neckTop: CGFloat
    let neckBottom: CGFloat
    let radius: CGFloat     // widest half-width of a bulb
    let neck: CGFloat       // half-width of the neck
    let capHeight: CGFloat
    private let cumulative: [Double]   // area from the cap to t, sampled; last element is the whole bulb

    static let samples = 240

    init(size: CGSize) {
        capHeight = 9
        cx = size.width / 2
        radius = min(size.width * 0.3, size.height * 0.31)
        neck = 3
        let neckLength: CGFloat = 6
        yTop = capHeight + 1
        yBottom = size.height - capHeight - 1
        neckTop = size.height / 2 - neckLength / 2
        neckBottom = size.height / 2 + neckLength / 2
        var cum = [0.0]
        for i in 1...Self.samples {
            let t0 = Double(i - 1) / Double(Self.samples), t1 = Double(i) / Double(Self.samples)
            let w = Double(Self.halfWidth(t0, radius, neck) + Self.halfWidth(t1, radius, neck))
            cum.append(cum[i - 1] + w * (t1 - t0))
        }
        cumulative = cum
    }

    var bulbHeight: CGFloat { neckTop - yTop }

    /// Half-width of a bulb at t (0 at its cap, 1 at the neck): rounded near the cap, widest about a
    /// third of the way in, narrowing to the neck.
    static func halfWidth(_ t: Double, _ radius: CGFloat, _ neck: CGFloat) -> CGFloat {
        let u = 0.22 + 0.78 * min(1, max(0, t))
        return neck + (radius - neck) * CGFloat(pow(max(0, sin(Double.pi * u)), 0.85))
    }

    func r(_ t: Double) -> CGFloat { Self.halfWidth(t, radius, neck) }
    func yUpper(_ t: Double) -> CGFloat { yTop + CGFloat(t) * bulbHeight }
    func yLower(_ t: Double) -> CGFloat { yBottom - CGFloat(t) * bulbHeight }

    /// The t at which sand fills `fraction` of a bulb measured from its cap (by area, so the level
    /// moves the way sand really would in a curved glass).
    func t(capFraction fraction: Double) -> Double {
        let target = min(1, max(0, fraction)) * cumulative[Self.samples]
        var lo = 0, hi = Self.samples
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] < target { lo = mid } else { hi = mid }
        }
        let a = cumulative[lo], b = cumulative[hi]
        let f = b > a ? (target - a) / (b - a) : 0
        return (Double(lo) + f) / Double(Self.samples)
    }

    /// Top sand surface for a share of light still to come: the sand fills from the neck up.
    func upperLevel(share: Double) -> Double { t(capFraction: 1 - share) }
    /// Bottom pile surface for a share already passed: the pile fills from the cap up.
    func lowerLevel(passed: Double) -> Double { t(capFraction: passed) }

    func outline() -> Path {
        var path = Path()
        let n = 60
        path.move(to: CGPoint(x: cx - r(0), y: yUpper(0)))
        for i in 1...n { let t = Double(i) / Double(n); path.addLine(to: CGPoint(x: cx - r(t), y: yUpper(t))) }
        path.addLine(to: CGPoint(x: cx - neck, y: neckBottom))
        for i in stride(from: n, through: 0, by: -1) {
            let t = Double(i) / Double(n); path.addLine(to: CGPoint(x: cx - r(t), y: yLower(t)))
        }
        path.addQuadCurve(to: CGPoint(x: cx + r(0), y: yLower(0)), control: CGPoint(x: cx, y: yBottom + 2))
        for i in 1...n { let t = Double(i) / Double(n); path.addLine(to: CGPoint(x: cx + r(t), y: yLower(t))) }
        path.addLine(to: CGPoint(x: cx + neck, y: neckTop))
        for i in stride(from: n, through: 0, by: -1) {
            let t = Double(i) / Double(n); path.addLine(to: CGPoint(x: cx + r(t), y: yUpper(t)))
        }
        path.addQuadCurve(to: CGPoint(x: cx - r(0), y: yUpper(0)), control: CGPoint(x: cx, y: yTop - 2))
        path.closeSubpath()
        return path
    }

    /// Sand in the top bulb between two levels (t from the cap; `to` nearer the neck), with a soft dip
    /// in the surface while it pours.
    func upperSand(from t0: Double, to t1: Double, dip: CGFloat) -> Path {
        var path = Path()
        let n = 40
        path.move(to: CGPoint(x: cx - r(t0), y: yUpper(t0)))
        for i in 1...n {
            let t = t0 + (t1 - t0) * Double(i) / Double(n)
            path.addLine(to: CGPoint(x: cx - r(t), y: yUpper(t)))
        }
        if t1 >= 0.999 {
            path.addLine(to: CGPoint(x: cx - neck, y: neckTop + 2))
            path.addLine(to: CGPoint(x: cx + neck, y: neckTop + 2))
        } else {
            path.addQuadCurve(to: CGPoint(x: cx + r(t1), y: yUpper(t1)),
                              control: CGPoint(x: cx, y: yUpper(t1) + dip))
        }
        for i in stride(from: n, through: 0, by: -1) {
            let t = t0 + (t1 - t0) * Double(i) / Double(n)
            path.addLine(to: CGPoint(x: cx + r(t), y: yUpper(t)))
        }
        path.addQuadCurve(to: CGPoint(x: cx - r(t0), y: yUpper(t0)),
                          control: CGPoint(x: cx, y: yUpper(t0) + dip))
        path.closeSubpath()
        return path
    }

    /// The bottom pile, from the cap up to level t, heaped where the stream lands.
    func lowerPile(level t1: Double, mound: CGFloat) -> Path {
        var path = Path()
        let n = 40
        path.move(to: CGPoint(x: cx - r(t1), y: yLower(t1)))
        for i in stride(from: n, through: 0, by: -1) {
            let t = t1 * Double(i) / Double(n); path.addLine(to: CGPoint(x: cx - r(t), y: yLower(t)))
        }
        path.addQuadCurve(to: CGPoint(x: cx + r(0), y: yLower(0)), control: CGPoint(x: cx, y: yBottom + 2))
        for i in 1...n {
            let t = t1 * Double(i) / Double(n); path.addLine(to: CGPoint(x: cx + r(t), y: yLower(t)))
        }
        path.addQuadCurve(to: CGPoint(x: cx - r(t1), y: yLower(t1)),
                          control: CGPoint(x: cx, y: yLower(t1) - mound * 2))
        path.closeSubpath()
        return path
    }
}

private struct HourglassDrawing {
    let snap: LightGlass.Snapshot
    let p: LightGlassPalette
    let size: CGSize

    static let minBandDepth: CGFloat = 3

    func draw(in ctx: inout GraphicsContext) {
        let g = HourglassGeometry(size: size)
        let glass = g.outline()
        let running = snap.mode == .running
        let share = snap.phase == nil ? 0 : snap.topShare
        let level = g.upperLevel(share: share)
        let pileLevel = g.lowerLevel(passed: snap.phase == nil ? 0 : 1 - share)
        let pileHeight = g.yLower(0) - g.yLower(pileLevel)
        let mound = min(10, max(0, pileHeight * 0.35))

        if p.starlit { drawStars(&ctx, g) }

        // Frame: two caps and two slim posts.
        let capHalf = g.radius + 14
        for y in [0, size.height - g.capHeight] {
            ctx.fill(Path(roundedRect: CGRect(x: g.cx - capHalf, y: y, width: capHalf * 2, height: g.capHeight),
                          cornerRadius: 3.5), with: .color(p.frame))
        }
        for x in [g.cx - capHalf + 6, g.cx + capHalf - 8.5] {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: g.capHeight, width: 2.5, height: size.height - 2 * g.capHeight),
                          cornerRadius: 1.2), with: .color(p.frame.opacity(0.45)))
        }

        ctx.fill(glass, with: .color(p.glassFill))

        var sandCtx = ctx
        sandCtx.clip(to: glass)

        // Top bulb: the light still to come.
        if share > 0.0005 {
            let surface = g.yUpper(level)
            let sand = g.upperSand(from: level, to: 1, dip: running ? 4 : 1.5)
            sandCtx.fill(sand, with: .linearGradient(Gradient(colors: p.sand),
                                                    startPoint: CGPoint(x: g.cx, y: surface),
                                                    endPoint: CGPoint(x: g.cx, y: g.neckTop)))
            if p.starlit { drawSparkles(&sandCtx, clip: sand, g, top: surface, bottom: g.neckTop) }

            // The block's layer: the light that pours through while it runs, and where the sand will stand.
            if snap.blockShare > 0.0005 {
                let after = g.upperLevel(share: max(0, share - snap.blockShare))
                // A Pomodoro is about 2% of a day's light, a sliver; draw the band at least 3 pt deep
                // so it reads, while the dashed line below stays at the true level.
                let drawnAfter = min(1, max(after, level + Double(Self.minBandDepth / g.bulbHeight)))
                let layer = g.upperSand(from: level, to: drawnAfter, dip: running ? 4 : 1.5)
                sandCtx.fill(layer, with: .color(p.band.opacity(0.92)))
                if after < 0.995 {
                    let y = g.yUpper(after)
                    var mark = Path()
                    mark.move(to: CGPoint(x: g.cx - g.r(after) + 2, y: y))
                    mark.addQuadCurve(to: CGPoint(x: g.cx + g.r(after) - 2, y: y),
                                      control: CGPoint(x: g.cx, y: y + (running ? 4 : 1.5)))
                    sandCtx.stroke(mark, with: .color(p.mark),
                                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 3]))
                }
            }
        }

        // Bottom bulb: the light already passed.
        if pileLevel > 0.002 {
            let pile = g.lowerPile(level: pileLevel, mound: mound)
            sandCtx.fill(pile, with: .linearGradient(Gradient(colors: p.spent),
                                                    startPoint: CGPoint(x: g.cx, y: g.yLower(pileLevel) - mound),
                                                    endPoint: CGPoint(x: g.cx, y: g.yBottom)))
        }

        // The stream: bold while a block runs; a hairline otherwise, because light passes either way.
        if share > 0.0005 && snap.mode != .paused {
            let top = g.neckTop - 1
            let bottom = pileLevel > 0.002 ? g.yLower(pileLevel) - mound : g.yBottom
            let w: CGFloat = running ? 2.2 : 1
            sandCtx.fill(Path(CGRect(x: g.cx - w / 2, y: top, width: w, height: max(0, bottom - top))),
                         with: .color(p.stream.opacity(running ? 1 : 0.5)))
        }

        drawSuns(&sandCtx, g)

        // Glass: outline and two quiet highlights.
        ctx.stroke(glass, with: .color(p.glassLine), lineWidth: 1.4)
        for upper in [true, false] {
            var shine = Path()
            for i in 0...20 {
                let t = 0.1 + 0.42 * Double(i) / 20
                let pt = CGPoint(x: g.cx - g.r(t) * 0.78, y: upper ? g.yUpper(t) : g.yLower(t))
                if i == 0 { shine.move(to: pt) } else { shine.addLine(to: pt) }
            }
            ctx.stroke(shine, with: .color(Color.white.opacity(p.starlit ? 0.18 : 0.75)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }

    /// Finished blocks, as small suns resting in the bottom bulb, row by row from the bottom.
    private func drawSuns(_ ctx: inout GraphicsContext, _ g: HourglassGeometry) {
        let shown = min(snap.suns, 18)
        guard shown > 0 else { return }
        let spacing: CGFloat = 19.5
        var placed = 0
        var row = 0
        while placed < shown && row < 6 {
            let y = g.yBottom - 11 - CGFloat(row) * 14
            let t = Double((g.yBottom - y) / g.bulbHeight)
            let half = g.r(t) - 11
            let fit = max(1, Int((half * 2) / spacing) + 1)
            let n = min(fit, shown - placed)
            let x0 = g.cx - CGFloat(n - 1) * spacing / 2 + (row % 2 == 1 ? 0 : 0)
            for i in 0..<n { drawSun(&ctx, at: CGPoint(x: x0 + CGFloat(i) * spacing, y: y)) }
            placed += n
            row += 1
        }
        if snap.suns > shown {
            ctx.draw(Text("+\(snap.suns - shown)").font(.system(size: 9, weight: .semibold)).foregroundColor(p.mark),
                     at: CGPoint(x: g.cx, y: g.yBottom - 11 - CGFloat(row) * 14))
        }
    }

    private func drawSun(_ ctx: inout GraphicsContext, at c: CGPoint) {
        var rays = Path()
        for k in 0..<8 {
            let a = Double(k) * .pi / 4
            rays.move(to: CGPoint(x: c.x + 5.6 * cos(a), y: c.y + 5.6 * sin(a)))
            rays.addLine(to: CGPoint(x: c.x + 7.8 * cos(a), y: c.y + 7.8 * sin(a)))
        }
        ctx.stroke(rays, with: .color(rgbSun(0xE8901C)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        let disc = Path(ellipseIn: CGRect(x: c.x - 4.3, y: c.y - 4.3, width: 8.6, height: 8.6))
        ctx.fill(disc, with: .radialGradient(Gradient(colors: [rgbSun(0xFFE07A), rgbSun(0xF4A324)]),
                                            center: CGPoint(x: c.x - 1.2, y: c.y - 1.2),
                                            startRadius: 0, endRadius: 5))
        ctx.stroke(disc, with: .color(rgbSun(0xC46F14).opacity(0.8)), lineWidth: 0.6)
    }

    private func rgbSun(_ hex: UInt32) -> Color { rgb(hex) }

    private func drawStars(_ ctx: inout GraphicsContext, _ g: HourglassGeometry) {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double(seed >> 11) / Double(1 << 53))
        }
        for _ in 0..<34 {
            let x = next() * size.width, y = next() * size.height, s = 0.6 + next() * 1.3
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                     with: .color(Color.white.opacity(0.25 + Double(next()) * 0.5)))
        }
    }

    /// Starlight in the night sand: a scatter of tiny bright grains.
    private func drawSparkles(_ ctx: inout GraphicsContext, clip: Path, _ g: HourglassGeometry,
                              top: CGFloat, bottom: CGFloat) {
        var c = ctx
        c.clip(to: clip)
        var seed: UInt64 = 0xD1B54A32D192ED03
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double(seed >> 11) / Double(1 << 53))
        }
        let w = g.radius * 2
        for _ in 0..<70 {
            let x = g.cx - g.radius + next() * w, y = top + next() * max(1, bottom - top), s = 0.7 + next() * 1.1
            c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                   with: .color(Color.white.opacity(0.35 + Double(next()) * 0.5)))
        }
    }
}
