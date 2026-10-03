import SwiftUI

// The Light Glass panel, in the Melting Glass look (the board's timer-dali.html): a hand-lettered
// "What's next?", the block's countdown with a gold colon that slowly drips, Horizon Time now and when
// the block ends, the painting (LightGlassPainting.swift), its caption, and the controls. Draws a
// LightGlass.Snapshot and nothing else, so the popover and the PNG render harness show the same picture.

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

/// The panel's paper and ink (the sketch's page colours): warm paper by day, the same drawing at night
/// on a dark one. The painting keeps its own palette (MeltPalette).
struct LightGlassPalette {
    var paper: Color
    var stain: Color
    var stain2: Color
    var ink: Color
    var ink2: Color
    var ink3: Color
    var ink4: Color
    var gold: Color
    var rose: Color
    var field: Color
    /// The sunlight's gold, as the painting's sand runs (starlight by night).
    var sand: [Color]
    var stream: Color
    var sun: Color
    var sunLo: Color
    var button: Color
    var buttonText: Color
    var starlit: Bool
    /// Every Paragonday page carries a teal accent: the mark in the header, teal on the primary
    /// button. Gold stays the sunlight's own colour. No glow.
    var brandMark: Color { Self.paragondayTeal }

    static let paragondayTeal = meltRGB(0x417B7D)

    static let day = LightGlassPalette(
        paper: meltRGB(0xF3E8D6), stain: meltRGB(0xC98A46, 0.12), stain2: meltRGB(0xB5685C, 0.09),
        ink: meltRGB(0x2A1D17), ink2: meltRGB(0x2A1D17, 0.82), ink3: meltRGB(0x2A1D17, 0.62), ink4: meltRGB(0x2A1D17, 0.22),
        gold: meltRGB(0x8A4F08), rose: meltRGB(0xA3402F), field: meltRGB(0xFFFAF0, 0.5),
        sand: [meltRGB(0xEEAE45), meltRGB(0xCF7A28)], stream: meltRGB(0xCF7A28),
        sun: meltRGB(0xEEAE45), sunLo: meltRGB(0xCF7A28),
        button: meltRGB(0x008080), buttonText: meltRGB(0xFBF3E4), starlit: false)

    static let night = LightGlassPalette(
        paper: meltRGB(0x1B1822), stain: meltRGB(0xC98A46, 0.07), stain2: meltRGB(0xA06078, 0.08),
        ink: meltRGB(0xF0E3CB), ink2: meltRGB(0xF0E3CB, 0.82), ink3: meltRGB(0xF0E3CB, 0.6), ink4: meltRGB(0xF0E3CB, 0.2),
        gold: meltRGB(0xF0B24F), rose: meltRGB(0xF0907A), field: meltRGB(0xF0E3CB, 0.06),
        sand: [meltRGB(0xD3DDF2), meltRGB(0x90A4CC)], stream: meltRGB(0xD3DDF2),
        sun: meltRGB(0xE8A33A), sunLo: meltRGB(0xBD6B1D),
        button: meltRGB(0x169F9F), buttonText: meltRGB(0x14121A), starlit: true)
}

// MARK: - Panel

struct LightGlassView: View {
    let snap: LightGlass.Snapshot
    var actions: LightGlassActions?

    static let width: CGFloat = 300
    static let paintingWidth: CGFloat = 268

    private var p: LightGlassPalette { snap.phase == .night ? .night : .day }
    private var breakWaiting: Bool { snap.mode == .idle && snap.offerKind == .rest }

    var body: some View {
        let scene = MeltScene(snap)
        VStack(alignment: .leading, spacing: 0) {
            header
            whatsNext.padding(.top, 9)
            statusRow.padding(.top, 6)
            countdown.padding(.top, 1)
            horizonLine.padding(.top, 1)
            if let n = noteLine { n.padding(.top, 4) }
            ZStack {
                MeltingGlassPainting(scene: scene).equatable()
                MeltingGlassMotion(scene: scene)
            }
            .frame(width: Self.paintingWidth, height: MeltingGlassPainting.height(forWidth: Self.paintingWidth))
            .padding(.top, 8)
            caption.padding(.top, 3)
            if let actions = actions { controls(actions).padding(.top, 11) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 15)
        .frame(width: Self.width)
        .background(PaperBackground(p: p).equatable())
    }

    // MARK: header and readout

    private var header: some View {
        HStack(spacing: 7) {
            ParagondayMark(color: p.brandMark).frame(height: 11)
            (Text("PARAGONDAY · ").foregroundColor(p.ink3) + Text("LIGHT GLASS").foregroundColor(p.ink))
                .font(MeltFont.type(9.5)).tracking(1.1)
            Spacer(minLength: 0)
        }
    }

    private var whatsNext: some View {
        let empty = snap.label.isEmpty
        let line = VStack(alignment: .leading, spacing: 1) {
            Text(empty ? "What's next?" : snap.label)
                .font(MeltFont.hand(19))
                .foregroundColor(empty ? p.ink3 : p.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(.clear).frame(height: 1)
                .overlay(Line().stroke(p.ink4, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5])))
        }
        return Group {
            if let a = actions {
                Button(action: a.editLabel) { line.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .help("What's next? Name the next block")
            } else {
                line
            }
        }
    }

    private var status: Text {
        func cap(_ s: String) -> Text { Text(s).foregroundColor(p.ink3) }
        func gold(_ s: String) -> Text { Text(s).foregroundColor(p.gold) }
        switch snap.mode {
        case .running where !snap.isRest:
            if snap.title == "Pomodoro" {
                return cap("FOCUS · POMODORO \(min(LightGlass.pomodorosPerLongBreak, snap.pomodorosInCycle + 1)) OF \(LightGlass.pomodorosPerLongBreak)")
            }
            return cap("FOCUS · \(snap.title.uppercased())")
        case .running:
            return cap(snap.title.uppercased())
        case .paused:
            return cap("PAUSED · ") + gold("THE LIGHT KEEPS FALLING")
        case .idle:
            if breakWaiting {
                // "Start 5-min break" on the button; here, what comes next: "5-MIN BREAK NEXT"
                let next = (snap.offerTitle ?? "break").replacingOccurrences(of: "Start ", with: "")
                return cap("BLOCK DONE · ") + gold("\(next.uppercased()) NEXT")
            }
            return cap("READY · \((snap.next?.title ?? "Pomodoro").uppercased())")
        }
    }

    /// The Pomodoro set shows only around a Pomodoro: one running, one next, or its break waiting.
    private var showsDots: Bool {
        switch snap.mode {
        case .running, .paused: return snap.title == "Pomodoro" || (snap.isRest && snap.pomodorosInCycle > 0)
        case .idle: return breakWaiting ? snap.pomodorosInCycle > 0 : snap.next?.title == "Pomodoro"
        }
    }

    private var statusRow: some View {
        HStack(alignment: .center, spacing: 8) {
            status.font(MeltFont.type(8.6)).tracking(0.9).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if showsDots {
                PomodoroDots(done: min(LightGlass.pomodorosPerLongBreak, snap.pomodorosInCycle),
                             current: snap.mode != .idle && !snap.isRest && snap.title == "Pomodoro", p: p)
            }
        }
    }

    private var countdownText: String {
        switch snap.mode {
        case .running, .paused: return snap.remainingText
        case .idle: return snap.next?.countdown ?? "—:—"
        }
    }

    @ViewBuilder private var countdown: some View {
        if breakWaiting {
            Text("Done.")
                .font(.system(size: 48, weight: .regular, design: .serif).italic())
                .foregroundColor(p.ink)
                .padding(.vertical, 2)
        } else {
            let parts = countdownText.split(separator: ":", maxSplits: 1).map(String.init)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(parts.first ?? "")
                if parts.count > 1 {
                    Text(":").foregroundColor(p.gold)
                        .overlay(alignment: .top) { ColonDrip(color: p.gold, fontSize: Self.bigSize) }
                        .padding(.horizontal, 1)
                    Text(parts[1])
                }
            }
            .font(.system(size: Self.bigSize, weight: .semibold, design: .serif).monospacedDigit())
            .tracking(-1.2)
            .foregroundColor(p.ink)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(countdownText)
        }
    }

    static let bigSize: CGFloat = 54

    /// "−3:45 tilset now → ends at −3:30 tilset", Horizon Time in the gold of the sunlight.
    private var horizonLine: some View {
        func plain(_ s: String) -> Text { Text(s).foregroundColor(p.ink2) }
        func gold(_ s: String) -> Text { Text(s).foregroundColor(p.gold) }
        /// "ends at −3:30 tilset if you resume now" → "ends at " + gold "−3:30 tilset" + " if you resume now".
        func ends(_ s: String) -> Text {
            guard s.hasPrefix("ends at ") else { return plain(s) }
            let rest = String(s.dropFirst("ends at ".count))
            if let r = rest.range(of: " if ") {
                return plain("ends at ") + gold(String(rest[..<r.lowerBound])) + plain(String(rest[r.lowerBound...]))
            }
            return plain("ends at ") + gold(rest)
        }
        var line = gold(snap.horizonNow) + plain(" now")
        switch snap.mode {
        case .running, .paused:
            if let e = snap.endsAtText { line = line + plain(" → ") + ends(e) }
        case .idle:
            if !breakWaiting, let n = snap.next { line = line + plain(" → ") + ends(n.endsAtText) + plain(" if started now") }
        }
        return line.font(MeltFont.type(10)).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
    }

    private var noteLine: AnyView? {
        let warn = snap.mode == .idle ? snap.next?.warning : snap.warning
        if let w = warn, !breakWaiting {
            return AnyView(Text(w).font(MeltFont.hand(13.5)).foregroundColor(p.rose).fixedSize(horizontal: false, vertical: true))
        }
        if let n = snap.note {
            return AnyView(Text(n).font(MeltFont.hand(13.5)).foregroundColor(p.ink2).fixedSize(horizontal: false, vertical: true))
        }
        return nil
    }

    private var caption: some View {
        (Text("The Persistence of Light").font(MeltFont.caption(11.5)).foregroundColor(p.ink2) +
         Text(snap.dayText.isEmpty ? "" : ", \(snap.dayText)").font(MeltFont.captionRoman(11.5)).foregroundColor(p.ink3))
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    // MARK: controls

    @ViewBuilder private func controls(_ a: LightGlassActions) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                switch snap.mode {
                case .running, .paused:
                    PrimaryButton(title: snap.mode == .paused ? "Resume" : "Pause", p: p, action: a.pauseResume)
                    SecondaryButton(title: snap.isRest ? "End break" : "Stop", p: p, action: a.stop)
                case .idle:
                    if let offer = snap.offerTitle {
                        PrimaryButton(title: offer, p: p, action: a.acceptOffer)
                        if breakWaiting { SecondaryButton(title: "Skip break", p: p, action: a.stop) }
                    } else {
                        PrimaryButton(title: "Start \(Int((snap.next?.minutes ?? 25).rounded())) min", p: p) { a.start(.pomodoro) }
                    }
                }
            }
            if snap.mode == .idle { presets(a) }
        }
    }

    private func presets(_ a: LightGlassActions) -> some View {
        let sunNumber = snap.phase == nil ? "—" : snap.horizonNow.components(separatedBy: " ").first ?? "—"
        let chosen = snap.offerKind == .rest ? nil : snap.next?.title
        let tiles: [(String, String, Bool, () -> Void)] = [
            ("25", "pomodoro", chosen == "Pomodoro", { a.start(.pomodoro) }),
            ("50", "+10 break", chosen == "Focus 50", { a.start(.focus50) }),
            ("90", "deep work", chosen == "Deep 90", { a.start(.deep90) }),
            ("···", "custom", chosen?.hasSuffix(" block") == true, a.custom),
            (sunNumber, snap.phase == .night ? "till sunrise" : "till sunset",
             chosen == "Until sunset" || chosen == "Until sunrise", { a.start(.untilSunset) }),
        ]
        return HStack(spacing: 6) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { i, t in
                PresetTile(number: t.0, caption: t.1, chosen: t.2, tilt: i % 2 == 1 ? 0.6 : (i % 3 == 2 ? -0.7 : 0), p: p, action: t.3)
            }
        }
    }
}

// MARK: - Pieces

private struct Line: Shape {
    func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)); return p }
}

/// Warm paper with two faint stains and its tooth; by night the same paper in the dark.
private struct PaperBackground: View, Equatable {
    let p: LightGlassPalette
    static func == (a: Self, b: Self) -> Bool { a.p.starlit == b.p.starlit }
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(p.paper))
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [p.stain, p.stain.opacity(0)]), center: CGPoint(x: size.width * 0.12, y: size.height * 0.06),
                                           startRadius: 0, endRadius: size.width * 0.75))
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [p.stain2, p.stain2.opacity(0)]), center: CGPoint(x: size.width * 0.92, y: size.height * 0.64),
                                           startRadius: 0, endRadius: size.width * 0.7))
            var t = ctx
            t.blendMode = p.starlit ? .screen : .multiply
            t.opacity = p.starlit ? 0.25 : 0.5
            let img = Image(decorative: MeltTexture.tooth, scale: 1).interpolation(.medium).resizable()
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width { t.draw(img, in: CGRect(x: x, y: y, width: 80, height: 80)); x += 80 }
                y += 80
            }
        }
        .allowsHitTesting(false)
    }
}

/// Four little suns for the Pomodoro set: filled when done, ringed for the one running.
private struct PomodoroDots: View {
    let done: Int
    let current: Bool
    let p: LightGlassPalette
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<LightGlass.pomodorosPerLongBreak, id: \.self) { i in
                let on = i < done, now = current && i == done
                ZStack {
                    WobblyCircle(seed: 30 + i).fill(on ? p.sun : Color.clear)
                    WobblyCircle(seed: 30 + i).stroke(on || now ? p.sunLo : p.ink3, lineWidth: 1.2)
                    if now { WobblyCircle(seed: 40 + i).stroke(p.sun, lineWidth: 2).padding(2) }
                }
                .frame(width: 9, height: 9)
            }
        }
        .accessibilityLabel("\(done) of \(LightGlass.pomodorosPerLongBreak) pomodoros done")
    }
}

private struct WobblyCircle: Shape {
    let seed: Int
    func path(in r: CGRect) -> Path {
        let R = Hand.rand(seed), k1 = R() * 6.28, k2 = R() * 6.28
        let pts: [CGPoint] = (0..<14).map { i in
            let a = Double(i) / 14 * 2 * .pi
            let rr = 1 + 0.06 * (0.6 * sin(a * 2 + k1) + 0.4 * sin(a * 3 + k2))
            return CGPoint(x: r.midX + cos(a) * r.width / 2 * rr, y: r.midY + sin(a) * r.height / 2 * rr)
        }
        return Hand.curve(pts, closed: true)
    }
}

/// The drop that gathers under the countdown's colon, swells, and falls (still under Reduce Motion).
private struct ColonDrip: View {
    let color: Color
    let fontSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion)) { tl in
            let (sx, sy, dy, op) = reduceMotion ? (0.8, 0.6, 0.0, 1.0) : frame(tl.date.timeIntervalSinceReferenceDate)
            Drop()
                .fill(color)
                .frame(width: fontSize * 0.07, height: fontSize * 0.1)
                .scaleEffect(x: sx, y: sy, anchor: .top)
                .offset(y: fontSize * 0.705 + dy * fontSize)
                .opacity(op)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The sketch's keyframes over 14 seconds: gather, swell, stretch, fall and vanish.
    private func frame(_ t: Double) -> (CGFloat, CGFloat, CGFloat, Double) {
        let f = t.truncatingRemainder(dividingBy: 14) / 14
        func e(_ a: Double, _ b: Double, _ u: Double) -> CGFloat { CGFloat(a + (b - a) * u * u * (3 - 2 * u)) }
        switch f {
        case ..<0.62: let u = f / 0.62; return (e(0.4, 1, u), e(0.1, 1, u), 0, 1)
        case ..<0.72: let u = (f - 0.62) / 0.1; return (e(1, 0.85, u), e(1, 1.5, u), 0, 1)
        case ..<0.77: let u = (f - 0.72) / 0.05; return (e(0.85, 0.7, u), e(1.5, 1.2, u), CGFloat(0.3 * u * u), 1 - u)
        default: return (0.4, 0.1, 0, 0)
        }
    }
}

private struct Drop: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX + r.width * 0.25, y: r.minY + r.height * 0.55),
                   control2: CGPoint(x: r.maxX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY), control1: CGPoint(x: r.minX, y: r.maxY),
                   control2: CGPoint(x: r.minX - r.width * 0.25, y: r.minY + r.height * 0.55))
        return p
    }
}

/// The sketch's buttons: a soft, uneven pill, the primary in Paragonday teal with a second outline
/// inked slightly off it, as if over the paint.
private struct PrimaryButton: View {
    let title: String
    let p: LightGlassPalette
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(MeltFont.type(11)).tracking(1.1)
                .foregroundColor(p.buttonText)
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(UnevenRoundedRectangle(topLeadingRadius: 17, bottomLeadingRadius: 15, bottomTrailingRadius: 18, topTrailingRadius: 14)
                    .fill(p.button))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 15, bottomLeadingRadius: 18, bottomTrailingRadius: 14, topTrailingRadius: 17)
                    .stroke(p.ink2, lineWidth: 1.1)
                    .padding(EdgeInsets(top: -2, leading: -3, bottom: -1.5, trailing: -1.5))
                    .rotationEffect(.degrees(-0.5)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SecondaryButton: View {
    let title: String
    let p: LightGlassPalette
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(MeltFont.type(11)).tracking(1.1)
                .foregroundColor(p.ink)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 18, bottomTrailingRadius: 15, topTrailingRadius: 17)
                    .stroke(p.ink2, lineWidth: 1.3))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One of the five lengths, as a small card; the one the primary button starts is circled by hand in teal.
private struct PresetTile: View {
    let number: String
    let caption: String
    let chosen: Bool
    let tilt: Double
    let p: LightGlassPalette
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(number)
                    .font(.system(size: number.count >= 5 ? 12.5 : 16.5, weight: .semibold, design: .serif).monospacedDigit())
                    .foregroundColor(chosen ? p.ink : p.ink2)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(caption)
                    .font(MeltFont.hand(9.5))
                    .foregroundColor(chosen ? p.ink : p.ink3)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 13, bottomTrailingRadius: 8, topTrailingRadius: 14).fill(p.field))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 13, bottomTrailingRadius: 8, topTrailingRadius: 14)
                .stroke(chosen ? Color.clear : p.ink4, lineWidth: 1.3))
            .overlay(chosen ? HandRing().stroke(p.button, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .padding(EdgeInsets(top: -5, leading: -5, bottom: -4, trailing: -4)) : nil)
            .rotationEffect(.degrees(tilt))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The sketch's hand-drawn circle around the chosen length (its mask path, stretched to the card).
private struct HandRing: Shape {
    func path(in r: CGRect) -> Path {
        func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x / 100 * r.width, y: r.minY + y / 70 * r.height) }
        var p = Path()
        p.move(to: q(30, 6))
        p.addCurve(to: q(95, 31), control1: q(60, 1), control2: q(93, 8))
        p.addCurve(to: q(45, 65), control1: q(97, 53), control2: q(73, 66))
        p.addCurve(to: q(5, 33), control1: q(17, 64), control2: q(3, 51))
        p.addCurve(to: q(53, 6), control1: q(7, 15), control2: q(27, 7))
        p.addCurve(to: q(82, 14), control1: q(65, 6), control2: q(75, 9))
        return p
    }
}

// MARK: - The mark

/// The Paragonday mark: a ring crossed by a gently curved horizon. Geometry from the brand's
/// paragonday-mark.svg (viewBox 0 56 256 140; ring at 128,124, r 53; horizon M14 152 Q128 96 244 146;
/// stroke 9, round caps), scaled to the frame's height. At header size the stroke is held at 1.2 pt so
/// the ring doesn't thin to a hairline.
struct ParagondayMark: View {
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let s = size.height / 140
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: (y - 56) * s) }
            var path = Path(ellipseIn: CGRect(x: 75 * s, y: 15 * s, width: 106 * s, height: 106 * s))
            path.move(to: pt(14, 152))
            path.addQuadCurve(to: pt(244, 146), control: pt(128, 96))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(1.2, 9 * s), lineCap: .round))
        }
        .aspectRatio(256 / 140, contentMode: .fit)
        .accessibilityLabel("Paragonday")
    }
}
