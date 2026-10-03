import Foundation

/// Light Glass: an hourglass focus timer whose sand is daylight.
///
/// Everything here is plain Foundation so it can be compiled into the test executable on its own:
/// the block state machine, the light-share maths, today's tally and the persistence key.
/// The menu, popover, bell and notifications live in LightGlassController.swift.
///
/// Every function takes `now` (and the sun's times through a `Daylight` provider) instead of
/// reading the clock, so a test can walk a whole day in a few lines.
struct LightGlass: Codable, Equatable {

    // MARK: - Persistence

    enum Keys {
        /// The whole running state (block, offer, label, pomodoro count, today's tally), JSON-encoded.
        static let state = "LightGlassState"
    }

    // MARK: - Sun

    /// Sunrise and sunset of one civil day.
    struct DaySpan: Equatable {
        var sunrise: Date
        var sunset: Date
    }

    /// Returns the sun's times for the civil day containing the given instant, or nil when unknown
    /// (no location yet, or polar day/night). The app backs it with its own solar window and SolarMath.
    typealias Daylight = (Date) -> DaySpan?

    enum Phase: String, Codable {
        case day, night
    }

    /// The stretch of light (sunrise to sunset) or night (sunset to the next sunrise) that `now` sits in.
    /// This is what the top bulb holds.
    struct Sky: Equatable {
        var phase: Phase
        var start: Date
        var end: Date

        var span: TimeInterval { end.timeIntervalSince(start) }

        /// Share of this light (or this night) still to come, 0...1.
        func share(at now: Date) -> Double {
            guard span > 0 else { return 0 }
            return LightGlass.clamp(end.timeIntervalSince(now) / span)
        }

        /// "tilset" by day, "tilrise" by night, as the menu bar says it.
        var word: String { phase == .day ? "tilset" : "tilrise" }
    }

    static func sky(at now: Date, daylight: Daylight, calendar: Calendar = .current) -> Sky? {
        guard let today = daylight(now) else { return nil }
        if now < today.sunrise {
            guard let y = calendar.date(byAdding: .day, value: -1, to: now),
                  let yesterday = daylight(y) else { return nil }
            return Sky(phase: .night, start: yesterday.sunset, end: today.sunrise)
        }
        if now < today.sunset {
            return Sky(phase: .day, start: today.sunrise, end: today.sunset)
        }
        guard let t = calendar.date(byAdding: .day, value: 1, to: now),
              let tomorrow = daylight(t) else { return nil }
        return Sky(phase: .night, start: today.sunset, end: tomorrow.sunrise)
    }

    /// Horizon Time at any instant, in the menu bar's single-display format ("−4:47 tilset",
    /// "−9:02 tilrise"). Mirrors ParagondayController.computeDisplay/signedHM so a block's end can be
    /// read the same way the menu bar reads the present; it does not replace that code.
    static func horizon(at instant: Date, daylight: Daylight, calendar: Calendar = .current) -> String {
        guard let sky = sky(at: instant, daylight: daylight, calendar: calendar) else { return "—:— tilset" }
        return "\(signedHM(instant.timeIntervalSince(sky.end))) \(sky.word)"
    }

    /// Seconds of the given running stretches that fell between a sunrise and a sunset.
    static func lightSeconds(in segments: [Segment], daylight: Daylight,
                             calendar: Calendar = .current) -> TimeInterval {
        var total: TimeInterval = 0
        for seg in segments where seg.end > seg.start {
            var day = calendar.startOfDay(for: seg.start)
            let lastDay = calendar.startOfDay(for: seg.end)
            while day <= lastDay {
                let noon = calendar.date(byAdding: .hour, value: 12, to: day) ?? day
                if let span = daylight(noon) {
                    let s = max(seg.start, span.sunrise)
                    let e = min(seg.end, span.sunset)
                    if e > s { total += e.timeIntervalSince(s) }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return total
    }

    // MARK: - Blocks

    enum Preset: String, Codable, CaseIterable {
        case pomodoro, focus50, deep90, untilSunset, custom

        /// Fixed length in minutes; nil for the two that are chosen at start.
        var fixedMinutes: Double? {
            switch self {
            case .pomodoro: return 25
            case .focus50: return 50
            case .deep90: return 90
            case .untilSunset, .custom: return nil
            }
        }

        /// Break offered when a block of this kind finishes (the web sketch's numbers: 5, 10, 20, and a
        /// fifth of a custom block, so 40 minutes earns 8). Until-sunset has none: the dark is the break.
        func breakMinutes(afterFocus seconds: TimeInterval) -> Double {
            switch self {
            case .pomodoro: return 5
            case .focus50: return 10
            case .deep90: return 20
            case .untilSunset: return 0
            case .custom: return max(1, (seconds / 60 / 5).rounded())
            }
        }

        func title(phase: Phase?) -> String {
            switch self {
            case .pomodoro: return "Pomodoro"
            case .focus50: return "Focus 50"
            case .deep90: return "Deep 90"
            case .untilSunset: return phase == .night ? "Until sunrise" : "Until sunset"
            case .custom: return "Custom"
            }
        }
    }

    static let longBreakMinutes: Double = 15
    static let pomodorosPerLongBreak = 4
    /// Half an hour after a block ends, the moment for its offer has passed: a block that ran out
    /// that long before the app noticed (it was quit, or the Mac slept) is counted without one, and
    /// an offer left waiting that long is dropped.
    static let staleOfferSeconds: TimeInterval = 30 * 60

    enum Kind: String, Codable {
        case focus, rest
    }

    struct Segment: Codable, Equatable {
        var start: Date
        var end: Date
    }

    struct Block: Codable, Equatable {
        var kind: Kind
        var preset: Preset
        var label: String
        var duration: TimeInterval
        var longRest: Bool = false
        /// For a break: the focus length to offer when it ends.
        var followUpMinutes: Double?
        var startedAt: Date
        /// Set while running.
        var endsAt: Date?
        /// Set while paused.
        var pausedRemaining: TimeInterval?
        /// Start of the stretch that is running now.
        var runStart: Date?
        /// Finished running stretches (a pause closes one).
        var segments: [Segment] = []

        var isPaused: Bool { pausedRemaining != nil }

        func remaining(at now: Date) -> TimeInterval {
            if let r = pausedRemaining { return r }
            guard let e = endsAt else { return 0 }
            return max(0, e.timeIntervalSince(now))
        }

        /// When it will end if it keeps running from `now` (a paused block is treated as resumed now).
        func projectedEnd(at now: Date) -> Date { now.addingTimeInterval(remaining(at: now)) }

        func progress(at now: Date) -> Double {
            guard duration > 0 else { return 1 }
            return LightGlass.clamp(1 - remaining(at: now) / duration)
        }

        func title(phase: Phase?) -> String {
            if kind == .rest { return longRest ? "Long break" : "Break" }
            if preset == .custom { return LightGlass.span(duration) + " block" }
            return preset.title(phase: phase)
        }
    }

    /// What one click starts once a block has finished: a break after focus, the next focus after a break.
    struct Offer: Codable, Equatable {
        var kind: Kind
        var preset: Preset
        var minutes: Double
        var longRest: Bool = false
        var focusMinutes: Double?

        /// "Start 5-min break" / "Start 25 min", as the web sketch words them.
        var title: String {
            kind == .rest ? "Start \(Int(minutes.rounded()))-min break" : "Start \(Int(minutes.rounded())) min"
        }
    }

    /// The block that just finished, kept until the next one starts, for the quiet line under the glass.
    struct Done: Codable, Equatable {
        var kind: Kind
        var label: String
        var duration: TimeInterval
        var lightSeconds: TimeInterval
        var longRest: Bool
    }

    struct Tally: Codable, Equatable {
        var day: String
        var blocks: Int = 0
        var focusSeconds: TimeInterval = 0
        var lightSeconds: TimeInterval = 0
        var nightSeconds: TimeInterval { max(0, focusSeconds - lightSeconds) }

        /// "4 blocks · 1 h 40 m of light"
        var line: String {
            if blocks == 0 { return "No blocks yet today" }
            var parts = ["\(blocks) block\(blocks == 1 ? "" : "s")"]
            let light = (lightSeconds / 60).rounded()
            let night = (nightSeconds / 60).rounded()
            if light > 0 || night == 0 { parts.append("\(LightGlass.span(lightSeconds)) of light") }
            if night > 0 { parts.append("\(LightGlass.span(nightSeconds)) of night") }
            return parts.joined(separator: " · ")
        }
    }

    enum Event: Equatable {
        /// A block ran out. `late` is how long ago it actually ended (non-zero after a relaunch).
        case finished(block: Block, lightSeconds: TimeInterval, late: TimeInterval, offer: Offer?)
    }

    // MARK: - State

    var block: Block?
    var offer: Offer?
    /// "What's next?": the label the next focus block takes (and the running one, if set mid-block).
    var label: String = ""
    var pomodorosInCycle: Int = 0
    var tally: Tally
    var done: Done?
    /// When the last block (or break) ended: the start of the light being let pass.
    var lastEnd: Date?

    init(now: Date, calendar: Calendar = .current) {
        tally = Tally(day: LightGlass.dayKey(now, calendar: calendar))
    }

    var isActive: Bool { block != nil }

    // MARK: - Transitions

    /// Length a preset would run if started now (until-sunset reads the sky). Nil when it can't run.
    func duration(of preset: Preset, minutes: Double? = nil, now: Date, daylight: Daylight,
                  calendar: Calendar = .current) -> TimeInterval? {
        let seconds: TimeInterval
        switch preset {
        case .untilSunset:
            guard let sky = LightGlass.sky(at: now, daylight: daylight, calendar: calendar) else { return nil }
            seconds = sky.end.timeIntervalSince(now)
        case .custom:
            guard let m = minutes else { return nil }
            seconds = m * 60
        default:
            seconds = (minutes ?? preset.fixedMinutes ?? 25) * 60
        }
        return seconds >= 60 ? seconds : nil
    }

    /// Starts a focus block, replacing anything running. Returns false if it can't run (until-sunset
    /// with the sun's times unknown or under a minute away, or a custom length under a minute).
    @discardableResult
    mutating func start(_ preset: Preset, minutes: Double? = nil, now: Date, daylight: Daylight,
                        calendar: Calendar = .current) -> Bool {
        guard let seconds = duration(of: preset, minutes: minutes, now: now, daylight: daylight,
                                     calendar: calendar) else { return false }
        rollover(now: now, calendar: calendar)
        block = Block(kind: .focus, preset: preset, label: label, duration: seconds,
                      startedAt: now, endsAt: now.addingTimeInterval(seconds), runStart: now)
        discardOffer()
        done = nil
        return true
    }

    /// Drops a waiting offer without taking it. Passing up the long break still closes the cycle of
    /// four, so the next Pomodoro starts a new one instead of earning another long break.
    private mutating func discardOffer() {
        if offer?.longRest == true { pomodorosInCycle = 0 }
        offer = nil
    }

    mutating func startRest(minutes: Double, long: Bool, preset: Preset, followUp: Double?, now: Date,
                            calendar: Calendar = .current) {
        rollover(now: now, calendar: calendar)
        let seconds = minutes * 60
        block = Block(kind: .rest, preset: preset, label: "", duration: seconds, longRest: long,
                      followUpMinutes: followUp, startedAt: now,
                      endsAt: now.addingTimeInterval(seconds), runStart: now)
        if long { pomodorosInCycle = 0 }
        offer = nil
        done = nil
    }

    /// The click after a block ends: start the offered break, or the next focus block.
    @discardableResult
    mutating func acceptOffer(now: Date, daylight: Daylight, calendar: Calendar = .current) -> Bool {
        guard let o = offer else { return false }
        switch o.kind {
        case .rest:
            startRest(minutes: o.minutes, long: o.longRest, preset: o.preset, followUp: o.focusMinutes,
                      now: now, calendar: calendar)
            return true
        case .focus:
            return start(o.preset, minutes: o.minutes, now: now, daylight: daylight, calendar: calendar)
        }
    }

    mutating func pause(now: Date) {
        guard var b = block, !b.isPaused, let ends = b.endsAt else { return }
        b.pausedRemaining = max(0, ends.timeIntervalSince(now))
        b.segments.append(Segment(start: b.runStart ?? b.startedAt, end: now))
        b.endsAt = nil
        b.runStart = nil
        block = b
    }

    mutating func resume(now: Date) {
        guard var b = block, let r = b.pausedRemaining else { return }
        b.endsAt = now.addingTimeInterval(r)
        b.runStart = now
        b.pausedRemaining = nil
        block = b
    }

    /// Ends the block (or skips a waiting offer) without counting it. Ending a break early still marks
    /// when the light started being let pass.
    mutating func stop(now: Date? = nil) {
        if block?.kind == .rest, let now = now { lastEnd = now }
        block = nil
        discardOffer()
        done = nil
    }

    mutating func setLabel(_ text: String) {
        label = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        if block?.kind == .focus { block?.label = label }
    }

    /// Advances the clock: finishes a block whose time is up (crediting it to the day it ended on),
    /// and starts a fresh tally when the day has turned. Call it every tick, and once after loading.
    mutating func tick(now: Date, daylight: Daylight, calendar: Calendar = .current) -> [Event] {
        var events: [Event] = []
        if var b = block, let ends = b.endsAt, ends <= now {
            b.segments.append(Segment(start: b.runStart ?? b.startedAt, end: ends))
            b.endsAt = nil
            b.runStart = nil
            block = nil

            var light: TimeInterval = 0
            var newOffer: Offer?
            if b.kind == .focus {
                light = LightGlass.lightSeconds(in: b.segments, daylight: daylight, calendar: calendar)
                credit(seconds: b.duration, light: light, endedAt: ends, calendar: calendar)
                if b.preset == .pomodoro { pomodorosInCycle += 1 }
                let long = b.preset == .pomodoro && pomodorosInCycle >= LightGlass.pomodorosPerLongBreak
                let minutes = long ? LightGlass.longBreakMinutes : b.preset.breakMinutes(afterFocus: b.duration)
                newOffer = minutes > 0
                    ? Offer(kind: .rest, preset: b.preset, minutes: minutes, longRest: long,
                            focusMinutes: b.duration / 60)
                    : nil
            } else {
                let next = b.followUpMinutes ?? b.preset.fixedMinutes ?? 25
                newOffer = Offer(kind: .focus, preset: b.preset, minutes: next)
            }
            let late = now.timeIntervalSince(ends)
            offer = newOffer
            if late > LightGlass.staleOfferSeconds { discardOffer() }
            done = Done(kind: b.kind, label: b.label, duration: b.duration, lightSeconds: light,
                        longRest: offer?.longRest ?? false)
            lastEnd = ends
            events.append(.finished(block: b, lightSeconds: light, late: late, offer: offer))
        } else if block == nil, offer != nil, let from = lastEnd,
                  now.timeIntervalSince(from) > LightGlass.staleOfferSeconds {
            // Left waiting half an hour: the offer goes, and the line under the glass moves on to
            // the light let pass since.
            discardOffer()
            done = nil
        }
        rollover(now: now, calendar: calendar)
        return events
    }

    private mutating func credit(seconds: TimeInterval, light: TimeInterval, endedAt: Date,
                                 calendar: Calendar) {
        let key = LightGlass.dayKey(endedAt, calendar: calendar)
        if key < tally.day { return }          // it ended on a day already gone
        if key > tally.day { tally = Tally(day: key) }
        tally.blocks += 1
        tally.focusSeconds += seconds
        tally.lightSeconds += light
    }

    /// A new day: a fresh tally, the pomodoro count back to zero, yesterday's waiting offer dropped.
    private mutating func rollover(now: Date, calendar: Calendar) {
        let key = LightGlass.dayKey(now, calendar: calendar)
        guard key != tally.day else { return }
        tally = Tally(day: key)
        if block == nil {
            offer = nil
            done = nil
            pomodorosInCycle = 0
        }
    }

    // MARK: - Reading it

    /// How far a block ending at `end` runs past the sunset ahead of it (by night, the sunrise), or
    /// nil when it ends before (or under 30 seconds after, as the web sketch allows).
    static func pastEdge(endingAt end: Date, now: Date, daylight: Daylight,
                         calendar: Calendar = .current) -> (seconds: TimeInterval, edge: String)? {
        guard let sky = sky(at: now, daylight: daylight, calendar: calendar) else { return nil }
        let over = end.timeIntervalSince(sky.end)
        return over > 30 ? (over, sky.phase == .day ? "sunset" : "sunrise") : nil
    }

    /// Menu title for a preset, with its length when chosen by the sky and a gentle warning when it
    /// would run past sunset: "Deep 90 · ends 1 h 10 m after sunset", "Until sunset (2 h 41 m)".
    func menuTitle(for preset: Preset, now: Date, daylight: Daylight, calendar: Calendar = .current) -> String {
        let phase = LightGlass.sky(at: now, daylight: daylight, calendar: calendar)?.phase
        var title = preset == .pomodoro ? "Start Pomodoro" : preset.title(phase: phase)
        if preset == .custom { return "Custom length…" }
        guard let d = duration(of: preset, now: now, daylight: daylight, calendar: calendar) else {
            return title
        }
        if preset == .untilSunset { title += " (\(LightGlass.spanDown(d)))" }
        if preset != .untilSunset,
           let past = LightGlass.pastEdge(endingAt: now.addingTimeInterval(d), now: now,
                                          daylight: daylight, calendar: calendar) {
            title += " · ends \(LightGlass.span(past.seconds)) after \(past.edge)"
        }
        return title
    }

    /// Menu-bar text while a block runs: the time left ("18:42"), or nil when idle.
    func statusText(now: Date) -> String? {
        guard let b = block else { return nil }
        let clock = LightGlass.clock(b.remaining(at: now))
        if b.isPaused { return "\(clock) paused" }
        return b.kind == .rest ? "\(clock) break" : clock
    }

    struct Snapshot: Equatable {
        enum Mode: Equatable { case idle, running, paused }

        var mode: Mode
        var phase: Phase?
        var horizonNow: String
        /// "2 h 41 m of light left" / "7 h 12 m until sunrise"
        var leftText: String
        /// Top bulb: share of this light (or night) still to come.
        var topShare: Double
        /// The top layer of that sand that pours through during the block (0 when idle).
        var blockShare: Double
        var isRest: Bool
        var title: String
        var label: String
        var remainingText: String
        var progress: Double
        var endsAtText: String?
        var warning: String?
        /// One quiet line, as on the web: the block just done, "Break over. What's next?", or the light
        /// let pass since the last block.
        var note: String?
        /// Finished focus blocks today, drawn as small suns in the bottom bulb.
        var suns: Int
        var todayLine: String
        var offerTitle: String?
        var pomodorosInCycle: Int
    }

    func snapshot(now: Date, daylight: Daylight, calendar: Calendar = .current) -> Snapshot {
        let sky = LightGlass.sky(at: now, daylight: daylight, calendar: calendar)
        let top = sky?.share(at: now) ?? 0
        var leftText = "Sun times unknown"
        if let sky = sky {
            let left = LightGlass.spanDown(sky.end.timeIntervalSince(now))
            leftText = sky.phase == .day ? "\(left) of light left" : "\(left) until sunrise"
        }

        var snap = Snapshot(mode: .idle, phase: sky?.phase,
                            horizonNow: LightGlass.horizon(at: now, daylight: daylight, calendar: calendar),
                            leftText: leftText, topShare: top, blockShare: 0, isRest: false,
                            title: "Light Glass", label: label, remainingText: "", progress: 0,
                            endsAtText: nil, warning: nil, note: nil, suns: tally.blocks,
                            todayLine: tally.line, offerTitle: offer?.title,
                            pomodorosInCycle: pomodorosInCycle)

        guard let b = block else {
            snap.note = idleNote(now: now, sky: sky, daylight: daylight, calendar: calendar)
            return snap
        }
        let remaining = b.remaining(at: now)
        let end = b.projectedEnd(at: now)
        snap.mode = b.isPaused ? .paused : .running
        snap.isRest = b.kind == .rest
        snap.title = b.title(phase: sky?.phase)
        snap.label = b.kind == .rest ? "" : b.label
        snap.remainingText = LightGlass.clock(remaining)
        snap.progress = b.progress(at: now)
        if let sky = sky, sky.span > 0 {
            snap.blockShare = min(top, remaining / sky.span)
        }
        let endsAt = "ends at \(LightGlass.horizon(at: end, daylight: daylight, calendar: calendar))"
        snap.endsAtText = b.isPaused ? "\(endsAt) if you resume now" : endsAt
        if b.kind == .focus, b.preset != .untilSunset,
           let past = LightGlass.pastEdge(endingAt: end, now: now, daylight: daylight, calendar: calendar) {
            snap.warning = "This block ends \(LightGlass.words(past.seconds)) after \(past.edge)."
        }
        return snap
    }

    private func idleNote(now: Date, sky: Sky?, daylight: Daylight, calendar: Calendar) -> String? {
        if let d = done {
            if d.kind == .rest { return "Break over. What's next?" }
            let who = d.label.isEmpty ? "" : "\(d.label): "
            if offer?.kind == .rest {
                let which = d.longRest ? "long break" : "break"
                return "\(who)\(LightGlass.span(d.duration)) done. The \(which) starts when you click."
            }
            let spent = d.lightSeconds >= 60 ? "\(LightGlass.span(d.lightSeconds)) of light"
                                             : "\(LightGlass.span(d.duration - d.lightSeconds)) of night"
            return "Block done\(d.label.isEmpty ? "" : ": \(d.label)"), \(spent)."
        }
        // The light let pass since the last block, within this sun cycle (since the sunrise that began it).
        guard let from = lastEnd, let sky = sky, now.timeIntervalSince(from) >= 60 else { return nil }
        let cycleStart = sky.phase == .day ? sky.start : (daylight(sky.start)?.sunrise ?? sky.start)
        guard from >= cycleStart else { return nil }
        let light = LightGlass.lightSeconds(in: [Segment(start: from, end: now)], daylight: daylight,
                                            calendar: calendar)
        let night = now.timeIntervalSince(from) - light
        let parts = [light >= 60 ? "\(LightGlass.span(light)) of light" : "",
                     night >= 60 ? "\(LightGlass.span(night)) of night" : ""].filter { !$0.isEmpty }
        return "Since your last block: \(parts.joined(separator: " and ")) has passed."
    }

    // MARK: - Saving

    static func load(from defaults: UserDefaults, now: Date, calendar: Calendar = .current) -> LightGlass {
        if let data = defaults.data(forKey: Keys.state),
           let saved = try? JSONDecoder().decode(LightGlass.self, from: data) {
            return saved
        }
        return LightGlass(now: now, calendar: calendar)
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Keys.state)
        }
    }

    // MARK: - Formatting

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "18:42", or "1:12:05" past the hour. Rounds up, so a fresh Pomodoro reads 25:00.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "1 h 40 m", "25 m", "2 h", to the nearest minute.
    static func span(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) m" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) m"
    }

    /// Like `span`, but drops the seconds the way Horizon Time does, so "4 h 16 m of light left"
    /// agrees with "−4:16 tilset" beside it.
    static func spanDown(_ seconds: TimeInterval) -> String {
        span((max(0, seconds) / 60).rounded(.down) * 60)
    }

    /// "1 hour 10 minutes", "43 minutes", for sentences (the web sketch's `words`).
    static func words(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let h = minutes / 60, m = minutes % 60
        let hw = h > 0 ? "\(h) hour\(h == 1 ? "" : "s")" : ""
        let mw = m > 0 ? "\(m) minute\(m == 1 ? "" : "s")" : ""
        return [hw, mw].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// "−H:MM" with a Unicode minus, seconds dropped, exactly as the menu bar prints Horizon Time.
    static func signedHM(_ seconds: TimeInterval) -> String {
        let total = Int(abs(seconds.rounded()))
        return String(format: "\u{2212}%d:%02d", total / 3600, (total % 3600) / 60)
    }

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}

// MARK: - Reading saved state
//
// Written out rather than synthesised so a state saved by another version still loads: a field with
// a default takes it when its key is missing, and a part that can't be read (a block, an offer, the
// tally) is dropped on its own instead of taking the running block and today's tally down with it.
// Encoding stays synthesised. In extensions, so the structs keep their memberwise initialisers.

extension LightGlass {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        block = try? c.decodeIfPresent(Block.self, forKey: .block)
        offer = try? c.decodeIfPresent(Offer.self, forKey: .offer)
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        pomodorosInCycle = (try? c.decodeIfPresent(Int.self, forKey: .pomodorosInCycle)) ?? 0
        // No readable tally: an empty one, which the first tick replaces with today's.
        tally = (try? c.decodeIfPresent(Tally.self, forKey: .tally)) ?? Tally(day: "")
        done = try? c.decodeIfPresent(Done.self, forKey: .done)
        lastEnd = try? c.decodeIfPresent(Date.self, forKey: .lastEnd)
    }
}

extension LightGlass.Block {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(LightGlass.Kind.self, forKey: .kind)
        preset = try c.decode(LightGlass.Preset.self, forKey: .preset)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        longRest = try c.decodeIfPresent(Bool.self, forKey: .longRest) ?? false
        followUpMinutes = try c.decodeIfPresent(Double.self, forKey: .followUpMinutes)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endsAt = try c.decodeIfPresent(Date.self, forKey: .endsAt)
        pausedRemaining = try c.decodeIfPresent(TimeInterval.self, forKey: .pausedRemaining)
        runStart = try c.decodeIfPresent(Date.self, forKey: .runStart)
        segments = try c.decodeIfPresent([LightGlass.Segment].self, forKey: .segments) ?? []
    }
}

extension LightGlass.Offer {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(LightGlass.Kind.self, forKey: .kind)
        preset = try c.decode(LightGlass.Preset.self, forKey: .preset)
        minutes = try c.decode(Double.self, forKey: .minutes)
        longRest = try c.decodeIfPresent(Bool.self, forKey: .longRest) ?? false
        focusMinutes = try c.decodeIfPresent(Double.self, forKey: .focusMinutes)
    }
}

extension LightGlass.Done {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(LightGlass.Kind.self, forKey: .kind)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        lightSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .lightSeconds) ?? 0
        longRest = try c.decodeIfPresent(Bool.self, forKey: .longRest) ?? false
    }
}

extension LightGlass.Tally {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        blocks = try c.decodeIfPresent(Int.self, forKey: .blocks) ?? 0
        focusSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .focusSeconds) ?? 0
        lightSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .lightSeconds) ?? 0
    }
}
