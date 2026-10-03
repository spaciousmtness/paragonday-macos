import Foundation

// Light Glass logic tests. No XCTest (the Command Line Tools don't need it): a tiny runner that
// prints each failure and exits non-zero if any. Run with scripts/test-lightglass.sh.

var passes = 0
var failures = 0
var current = ""

func test(_ name: String, _ body: () -> Void) {
    current = name
    let before = failures
    body()
    print(failures == before ? "ok    \(name)" : "FAIL  \(name)")
}

func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if cond { passes += 1 } else { failures += 1; print("  ✗ [\(current)] line \(line): \(msg)") }
}

func eq<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", line: Int = #line) {
    check(a == b, "\(msg) expected \(b), got \(a)", line: line)
}

func near(_ a: Double, _ b: Double, _ tol: Double = 0.001, _ msg: String = "", line: Int = #line) {
    check(abs(a - b) <= tol, "\(msg) expected \(b) ±\(tol), got \(a)", line: line)
}

// A simple sky: UTC, sunrise 06:00 and sunset 18:00 every day.
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "UTC")!

func at(_ day: Int, _ h: Int, _ m: Int = 0, _ s: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m, second: s))!
}

let sun: LightGlass.Daylight = { d in
    let start = cal.startOfDay(for: d)
    return .init(sunrise: start.addingTimeInterval(6 * 3600), sunset: start.addingTimeInterval(18 * 3600))
}

func fresh(_ now: Date) -> LightGlass { LightGlass(now: now, calendar: cal) }

func finishedOffer(_ events: [LightGlass.Event]) -> LightGlass.Offer? {
    guard case .finished(_, _, _, let offer)? = events.first else { return nil }
    return offer
}

// MARK: -

test("block countdown") {
    var g = fresh(at(3, 9))
    check(g.start(.pomodoro, now: at(3, 9), daylight: sun, calendar: cal), "pomodoro starts")
    eq(g.statusText(now: at(3, 9)), "25:00")
    eq(g.statusText(now: at(3, 9, 1)), "24:00")
    eq(g.statusText(now: at(3, 9, 24, 30)), "0:30")
    eq(g.tick(now: at(3, 9, 24, 59), daylight: sun, calendar: cal).count, 0, "still running at 24:59")

    let events = g.tick(now: at(3, 9, 25), daylight: sun, calendar: cal)
    eq(events.count, 1, "finishes at 25:00")
    if case .finished(let b, let light, let late, let offer)? = events.first {
        eq(b.kind, .focus); near(light, 1500, 0.5, "all daylight"); near(late, 0, 0.5, "on time")
        eq(offer?.kind, .rest); eq(offer?.minutes, 5); eq(offer?.title, "Start 5-min break")
    }
    check(g.block == nil, "block cleared")
    eq(g.statusText(now: at(3, 9, 25)), nil, "menu bar goes back to Horizon Time")
    eq(g.tally.blocks, 1); near(g.tally.focusSeconds, 1500); near(g.tally.lightSeconds, 1500)
    eq(g.tally.line, "1 block · 25 m of light")
}

test("pause and resume") {
    var g = fresh(at(3, 9))
    g.start(.pomodoro, now: at(3, 9), daylight: sun, calendar: cal)
    g.pause(now: at(3, 9, 10))
    g.pause(now: at(3, 9, 12))   // second pause is a no-op
    eq(g.statusText(now: at(3, 9, 20)), "15:00 paused", "time stands still while paused")
    eq(g.tick(now: at(3, 9, 40), daylight: sun, calendar: cal).count, 0, "a paused block never finishes")
    eq(g.snapshot(now: at(3, 9, 20), daylight: sun, calendar: cal).mode, .paused)

    g.resume(now: at(3, 9, 20))
    g.resume(now: at(3, 9, 21))  // resume while running is a no-op
    eq(g.block?.endsAt, at(3, 9, 35), "ends 15 minutes after resuming")
    eq(g.tick(now: at(3, 9, 34, 59), daylight: sun, calendar: cal).count, 0)
    let events = g.tick(now: at(3, 9, 35), daylight: sun, calendar: cal)
    if case .finished(let b, _, _, _)? = events.first {
        eq(b.segments, [.init(start: at(3, 9), end: at(3, 9, 10)), .init(start: at(3, 9, 20), end: at(3, 9, 35))])
    } else { check(false, "should finish") }
    near(g.tally.focusSeconds, 1500, 0.5, "counts the planned 25 minutes")
}

test("four pomodoros, then the long break") {
    var g = fresh(at(3, 8))
    var t = at(3, 8)
    g.start(.pomodoro, now: t, daylight: sun, calendar: cal)
    for i in 1...4 {
        t = g.block!.endsAt!
        let offer = finishedOffer(g.tick(now: t, daylight: sun, calendar: cal))
        eq(g.pomodorosInCycle, i, "pomodoro \(i) counted")
        if i < 4 {
            eq(offer?.minutes, 5, "short break after pomodoro \(i)"); eq(offer?.longRest, false)
        } else {
            eq(offer?.minutes, 15, "long break after the fourth"); eq(offer?.longRest, true)
            eq(offer?.title, "Start 15-min break")
        }
        check(g.acceptOffer(now: t, daylight: sun, calendar: cal), "the break starts on a click")
        eq(g.block?.kind, .rest)
        eq(g.statusText(now: t), i < 4 ? "5:00 break" : "15:00 break")
        t = g.block!.endsAt!
        let next = finishedOffer(g.tick(now: t, daylight: sun, calendar: cal))
        eq(next?.kind, .focus); eq(next?.title, "Start 25 min")
        if i == 4 { eq(g.pomodorosInCycle, 0, "the long break resets the cycle") }
        check(g.acceptOffer(now: t, daylight: sun, calendar: cal), "next pomodoro starts on a click")
        eq(g.block?.duration, 1500)
    }
    t = g.block!.endsAt!
    eq(finishedOffer(g.tick(now: t, daylight: sun, calendar: cal))?.minutes, 5, "a new cycle starts short")
    eq(g.tally.blocks, 5)
}

test("other presets offer their own breaks") {
    var g = fresh(at(3, 8))
    g.start(.focus50, now: at(3, 8), daylight: sun, calendar: cal)
    var offer = finishedOffer(g.tick(now: at(3, 8, 50), daylight: sun, calendar: cal))
    eq(offer?.minutes, 10)
    g.acceptOffer(now: at(3, 8, 50), daylight: sun, calendar: cal)
    offer = finishedOffer(g.tick(now: at(3, 9), daylight: sun, calendar: cal))
    eq(offer?.title, "Start 50 min")
    g.start(.custom, minutes: 40, now: at(3, 10), daylight: sun, calendar: cal)
    offer = finishedOffer(g.tick(now: at(3, 10, 40), daylight: sun, calendar: cal))
    eq(offer?.minutes, 8, "a custom block earns a fifth of its length, as on the web")
    g.acceptOffer(now: at(3, 10, 40), daylight: sun, calendar: cal)
    offer = finishedOffer(g.tick(now: at(3, 10, 48), daylight: sun, calendar: cal))
    eq(offer?.title, "Start 40 min")
    check(!g.start(.custom, minutes: 0.5, now: at(3, 11), daylight: sun, calendar: cal), "under a minute refused")
}

test("run-past-sunset warning") {
    let g = fresh(at(3, 17, 40))
    let now = at(3, 17, 40)   // sunset at 18:00
    eq(g.menuTitle(for: .pomodoro, now: now, daylight: sun, calendar: cal), "Start Pomodoro · ends 5 m after sunset")
    eq(g.menuTitle(for: .deep90, now: now, daylight: sun, calendar: cal), "Deep 90 · ends 1 h 10 m after sunset")
    eq(g.menuTitle(for: .untilSunset, now: now, daylight: sun, calendar: cal), "Until sunset (20 m)")
    eq(g.menuTitle(for: .pomodoro, now: at(3, 10), daylight: sun, calendar: cal), "Start Pomodoro")

    var p = g
    p.start(.pomodoro, now: now, daylight: sun, calendar: cal)
    let snap = p.snapshot(now: now, daylight: sun, calendar: cal)
    eq(snap.warning, "This block ends 5 minutes after sunset.")
    eq(snap.endsAtText, "ends at −11:55 tilrise")

    var u = g
    check(u.start(.untilSunset, now: now, daylight: sun, calendar: cal), "until sunset starts")
    eq(u.block?.duration, 1200)
    eq(u.snapshot(now: now, daylight: sun, calendar: cal).warning, nil, "until sunset never runs past it")

    var m = fresh(at(3, 10))
    m.start(.pomodoro, now: at(3, 10), daylight: sun, calendar: cal)
    let morning = m.snapshot(now: at(3, 10), daylight: sun, calendar: cal)
    eq(morning.warning, nil); eq(morning.endsAtText, "ends at −7:35 tilset")

    var late = fresh(at(3, 17, 59, 30))
    check(!late.start(.untilSunset, now: at(3, 17, 59, 30), daylight: sun, calendar: cal), "under a minute to sunset")
    eq(g.menuTitle(for: .untilSunset, now: at(3, 21), daylight: sun, calendar: cal), "Until sunrise (9 h)")
    eq(g.menuTitle(for: .deep90, now: at(3, 21), daylight: sun, calendar: cal), "Deep 90", "ends before sunrise")
    eq(g.menuTitle(for: .deep90, now: at(4, 5), daylight: sun, calendar: cal), "Deep 90 · ends 30 m after sunrise",
       "by night the edge is sunrise, as on the web")
    var d90 = fresh(at(3, 17))
    d90.start(.deep90, now: at(3, 17), daylight: sun, calendar: cal)
    eq(d90.snapshot(now: at(3, 17), daylight: sun, calendar: cal).warning, "This block ends 30 minutes after sunset.")
    d90.pause(now: at(3, 17, 10))
    eq(d90.snapshot(now: at(3, 17, 10), daylight: sun, calendar: cal).endsAtText, "ends at −11:30 tilrise if you resume now")
}

test("light share by day and by night") {
    let day = LightGlass.sky(at: at(3, 12), daylight: sun, calendar: cal)!
    eq(day.phase, .day); near(day.share(at: at(3, 12)), 0.5); eq(day.word, "tilset")
    near(LightGlass.sky(at: at(3, 6), daylight: sun, calendar: cal)!.share(at: at(3, 6)), 1, 0.001, "full at sunrise")

    let evening = LightGlass.sky(at: at(3, 21), daylight: sun, calendar: cal)!
    eq(evening.phase, .night); eq(evening.word, "tilrise")
    eq(evening.start, at(3, 18)); eq(evening.end, at(4, 6))
    near(evening.share(at: at(3, 21)), 0.75, 0.001, "night until sunrise, as a share of the whole night")
    let small = LightGlass.sky(at: at(3, 3), daylight: sun, calendar: cal)!
    eq(small.start, at(2, 18)); near(small.share(at: at(3, 3)), 0.25)

    let g = fresh(at(3, 21))
    let n = g.snapshot(now: at(3, 21), daylight: sun, calendar: cal)
    eq(n.phase, .night); eq(n.horizonNow, "−9:00 tilrise"); eq(n.leftText, "9 h until sunrise")
    let d = g.snapshot(now: at(3, 12), daylight: sun, calendar: cal)
    eq(d.horizonNow, "−6:00 tilset"); eq(d.leftText, "6 h of light left")
    let odd = g.snapshot(now: at(3, 12, 0, 40), daylight: sun, calendar: cal)
    eq(odd.horizonNow, "−5:59 tilset"); eq(odd.leftText, "5 h 59 m of light left", "agrees with Horizon Time")

    var b = fresh(at(3, 12))
    b.start(.pomodoro, now: at(3, 12), daylight: sun, calendar: cal)
    near(b.snapshot(now: at(3, 12), daylight: sun, calendar: cal).blockShare, 1500.0 / 43200, 1e-9, "the block's layer")

    eq(LightGlass.sky(at: at(3, 12), daylight: { _ in nil }, calendar: cal), nil, "unknown sky")
    eq(g.snapshot(now: at(3, 12), daylight: { _ in nil }, calendar: cal).horizonNow, "—:— tilset")
}

test("light and night in the tally") {
    var g = fresh(at(3, 17, 50))
    g.start(.pomodoro, now: at(3, 17, 50), daylight: sun, calendar: cal)   // straddles 18:00
    _ = g.tick(now: at(3, 18, 15), daylight: sun, calendar: cal)
    near(g.tally.lightSeconds, 600, 0.5); near(g.tally.nightSeconds, 900, 0.5)
    eq(g.tally.line, "1 block · 10 m of light · 15 m of night")

    var n = fresh(at(3, 21))
    n.start(.pomodoro, now: at(3, 21), daylight: sun, calendar: cal)
    _ = n.tick(now: at(3, 21, 25), daylight: sun, calendar: cal)
    eq(n.tally.line, "1 block · 25 m of night")

    var four = fresh(at(3, 9))
    for i in 0..<4 {
        four.start(.pomodoro, now: at(3, 9 + i), daylight: sun, calendar: cal)
        _ = four.tick(now: at(3, 9 + i, 25), daylight: sun, calendar: cal)
    }
    eq(four.tally.line, "4 blocks · 1 h 40 m of light")
    eq(fresh(at(3, 9)).tally.line, "No blocks yet today")
}

test("relaunch restore") {
    let suite = "LightGlassTests-\(ProcessInfo.processInfo.processIdentifier)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    var g = fresh(at(3, 9))
    g.setLabel("  Write the intro  ")
    g.start(.pomodoro, now: at(3, 9), daylight: sun, calendar: cal)
    g.save(to: defaults)

    var r = LightGlass.load(from: defaults, now: at(3, 9, 10), calendar: cal)
    eq(r, g, "state round-trips")
    eq(r.block?.label, "Write the intro")
    eq(r.tick(now: at(3, 9, 10), daylight: sun, calendar: cal).count, 0)
    eq(r.statusText(now: at(3, 9, 10)), "15:00", "keeps counting down across a relaunch")

    var gone = LightGlass.load(from: defaults, now: at(3, 9, 30), calendar: cal)
    let events = gone.tick(now: at(3, 9, 30), daylight: sun, calendar: cal)
    if case .finished(_, _, let lateBy, let offer)? = events.first {
        near(lateBy, 300, 0.5, "ended 5 minutes before the relaunch"); eq(offer?.minutes, 5)
    } else { check(false, "a block that ran out while closed finishes on launch") }
    eq(gone.tally.blocks, 1)

    var stale = LightGlass.load(from: defaults, now: at(3, 11), calendar: cal)
    _ = stale.tick(now: at(3, 11), daylight: sun, calendar: cal)
    eq(stale.tally.blocks, 1, "still counted"); eq(stale.offer, nil, "no break offered an hour and a half late")

    var p = fresh(at(3, 9))
    p.start(.focus50, now: at(3, 9), daylight: sun, calendar: cal)
    p.pause(now: at(3, 9, 10))
    p.save(to: defaults)
    var q = LightGlass.load(from: defaults, now: at(3, 13), calendar: cal)
    eq(q.tick(now: at(3, 13), daylight: sun, calendar: cal).count, 0)
    eq(q.statusText(now: at(3, 13)), "40:00 paused", "a paused block stays paused")
    q.resume(now: at(3, 13))
    eq(q.block?.endsAt, at(3, 13, 40))

    var y = fresh(at(3, 23))
    y.start(.pomodoro, now: at(3, 23), daylight: sun, calendar: cal)
    y.save(to: defaults)
    var next = LightGlass.load(from: defaults, now: at(4, 9), calendar: cal)
    _ = next.tick(now: at(4, 9), daylight: sun, calendar: cal)
    eq(next.tally.day, "2026-10-04"); eq(next.tally.blocks, 0, "yesterday's block is not today's")

    eq(LightGlass.load(from: UserDefaults(suiteName: suite + "-empty")!, now: at(3, 9), calendar: cal),
       fresh(at(3, 9)), "nothing saved: a clean glass")
}

test("a new day starts a fresh tally") {
    var g = fresh(at(3, 9))
    g.start(.pomodoro, now: at(3, 9), daylight: sun, calendar: cal)
    _ = g.tick(now: at(3, 9, 25), daylight: sun, calendar: cal)
    check(g.offer != nil && g.pomodorosInCycle == 1, "offer waiting")
    _ = g.tick(now: at(4, 0, 1), daylight: sun, calendar: cal)
    eq(g.tally.day, "2026-10-04"); eq(g.tally.blocks, 0); eq(g.offer, nil); eq(g.pomodorosInCycle, 0)
}

test("label, stop and formats") {
    var g = fresh(at(3, 9))
    g.start(.deep90, now: at(3, 9), daylight: sun, calendar: cal)
    g.setLabel(String(repeating: "x", count: 80))
    eq(g.block?.label.count, 60, "label capped")
    g.stop()
    check(g.block == nil && g.offer == nil, "stop clears"); eq(g.tally.blocks, 0, "a stopped block is not counted")
    check(!g.acceptOffer(now: at(3, 9), daylight: sun, calendar: cal), "nothing to accept")

    eq(LightGlass.horizon(at: at(3, 15, 13), daylight: sun, calendar: cal), "−2:47 tilset")
    eq(LightGlass.clock(3725), "1:02:05"); eq(LightGlass.clock(59.2), "1:00")
    eq(LightGlass.span(6000), "1 h 40 m"); eq(LightGlass.span(7200), "2 h"); eq(LightGlass.span(1500), "25 m")
}

test("the bell") {
    let wav = LightGlassBell.wav()
    eq(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
    eq(String(decoding: wav[8..<12], as: UTF8.self), "WAVE")
    eq(wav.count, 44 + 6 * 44_100 * 2, "6 s of mono 16-bit")
    let s = LightGlassBell.samples()
    near(s.map { abs($0) }.max() ?? 0, 0.55, 0.001, "soft peak")
    func rms(_ xs: ArraySlice<Double>) -> Double { (xs.reduce(0) { $0 + $1 * $1 } / Double(xs.count)).squareRoot() }
    let head = rms(s[0..<22_050]), tail = rms(s[(s.count - 22_050)...])
    check(head > tail * 8, "it decays (head \(head), tail \(tail))")
    near(s.last ?? 1, 0, 0.0001, "ends at silence")
    near(s.first ?? 1, 0, 0.0001, "starts without a click")
}

test("the quiet line: what just finished, and the light let pass") {
    var g = fresh(at(3, 9))
    g.setLabel("Venue shortlist")
    g.start(.pomodoro, now: at(3, 9), daylight: sun, calendar: cal)
    _ = g.tick(now: at(3, 9, 25), daylight: sun, calendar: cal)
    eq(g.snapshot(now: at(3, 9, 26), daylight: sun, calendar: cal).note,
       "Venue shortlist: 25 m done. The break starts when you click.")
    g.acceptOffer(now: at(3, 9, 26), daylight: sun, calendar: cal)
    eq(g.snapshot(now: at(3, 9, 27), daylight: sun, calendar: cal).note, nil, "nothing while a break runs")
    _ = g.tick(now: at(3, 9, 31), daylight: sun, calendar: cal)
    eq(g.snapshot(now: at(3, 9, 31), daylight: sun, calendar: cal).note, "Break over. What's next?")
    g.stop(now: at(3, 9, 32))   // not now
    eq(g.snapshot(now: at(3, 10, 11), daylight: sun, calendar: cal).note,
       "Since your last block: 40 m of light has passed.")

    var e = fresh(at(3, 17))
    e.start(.pomodoro, now: at(3, 17, 5), daylight: sun, calendar: cal)
    _ = e.tick(now: at(3, 17, 30), daylight: sun, calendar: cal)
    e.stop(now: at(3, 17, 30))
    eq(e.snapshot(now: at(3, 18, 20), daylight: sun, calendar: cal).note,
       "Since your last block: 30 m of light and 20 m of night has passed.")
    eq(e.snapshot(now: at(4, 7), daylight: sun, calendar: cal).note, nil, "a new sun cycle starts clean")

    var b = fresh(at(3, 10))
    b.start(.pomodoro, now: at(3, 10), daylight: sun, calendar: cal)
    b.acceptOffer(now: at(3, 10), daylight: sun, calendar: cal)
    b.offer = .init(kind: .rest, preset: .pomodoro, minutes: 5)
    b.acceptOffer(now: at(3, 10, 1), daylight: sun, calendar: cal)
    b.stop(now: at(3, 10, 3))
    eq(b.lastEnd, at(3, 10, 3), "ending a break early starts the light let pass")

    var u = fresh(at(3, 17, 40))
    u.setLabel("Invitation copy")
    u.start(.untilSunset, now: at(3, 17, 40), daylight: sun, calendar: cal)
    _ = u.tick(now: at(3, 18), daylight: sun, calendar: cal)
    eq(u.offer, nil, "the dark is the break")
    eq(u.snapshot(now: at(3, 18, 1), daylight: sun, calendar: cal).note, "Block done: Invitation copy, 20 m of light.")
    eq(LightGlass.words(4200), "1 hour 10 minutes"); eq(LightGlass.words(60), "1 minute"); eq(LightGlass.words(7200), "2 hours")
}

/// Runs `n` Pomodoros back to back from `t0`, taking each short break, and stops at the offer after
/// the last one. Returns when that last Pomodoro ended.
func pomodoros(_ g: inout LightGlass, _ n: Int, from t0: Date) -> Date {
    var t = t0
    for i in 1...n {
        g.start(.pomodoro, now: t, daylight: sun, calendar: cal)
        t = g.block!.endsAt!
        _ = g.tick(now: t, daylight: sun, calendar: cal)
        if i < n {
            g.acceptOffer(now: t, daylight: sun, calendar: cal)
            t = g.block!.endsAt!
            _ = g.tick(now: t, daylight: sun, calendar: cal)
        }
    }
    return t
}

test("passing up the long break starts a new cycle") {
    var g = fresh(at(3, 8))
    var t = pomodoros(&g, 4, from: at(3, 8))
    eq(g.offer?.longRest, true, "the fourth earns the long break"); eq(g.pomodorosInCycle, 4)
    g.stop(now: t)   // Skip break
    eq(g.pomodorosInCycle, 0, "skipping it closes the cycle")
    for i in 1...2 {
        g.start(.pomodoro, now: t, daylight: sun, calendar: cal)
        t = g.block!.endsAt!
        let offer = finishedOffer(g.tick(now: t, daylight: sun, calendar: cal))
        eq(offer?.minutes, 5, "pomodoro \(i) after the skip gets a short break"); eq(offer?.longRest, false)
        eq(g.pomodorosInCycle, i)
        g.stop(now: t)
    }

    var direct = fresh(at(3, 8))
    t = pomodoros(&direct, 4, from: at(3, 8))
    direct.start(.pomodoro, now: t, daylight: sun, calendar: cal)   // straight into the next one
    eq(direct.pomodorosInCycle, 0, "starting another Pomodoro instead also closes the cycle")
    eq(finishedOffer(direct.tick(now: direct.block!.endsAt!, daylight: sun, calendar: cal))?.minutes, 5)

    // The fourth runs out while the app is closed and the relaunch comes too late for its break.
    let suite = "LightGlassTests-cycle-\(ProcessInfo.processInfo.processIdentifier)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var closed = fresh(at(3, 8))
    t = pomodoros(&closed, 3, from: at(3, 8))
    closed.acceptOffer(now: t, daylight: sun, calendar: cal)
    t = closed.block!.endsAt!
    _ = closed.tick(now: t, daylight: sun, calendar: cal)
    closed.start(.pomodoro, now: t, daylight: sun, calendar: cal)
    let fourthEnds = closed.block!.endsAt!
    closed.save(to: defaults)
    var relaunched = LightGlass.load(from: defaults, now: fourthEnds.addingTimeInterval(3600), calendar: cal)
    let events = relaunched.tick(now: fourthEnds.addingTimeInterval(3600), daylight: sun, calendar: cal)
    eq(finishedOffer(events), nil, "no break an hour late"); eq(relaunched.tally.blocks, 4)
    eq(relaunched.pomodorosInCycle, 0, "a long break dropped as stale closes the cycle too")
}

test("a waiting offer expires after half an hour") {
    var g = fresh(at(3, 9))
    g.setLabel("Venue shortlist")
    g.start(.pomodoro, now: at(3, 9), daylight: sun, calendar: cal)
    _ = g.tick(now: at(3, 9, 25), daylight: sun, calendar: cal)
    _ = g.tick(now: at(3, 9, 54), daylight: sun, calendar: cal)
    eq(g.offer?.title, "Start 5-min break", "still offered 29 minutes on")
    eq(g.tick(now: at(3, 9, 56), daylight: sun, calendar: cal).count, 0)
    eq(g.offer, nil, "gone after 31"); eq(g.done, nil)
    eq(g.pomodorosInCycle, 1, "a short break dropped leaves the cycle alone")
    eq(g.snapshot(now: at(3, 9, 56), daylight: sun, calendar: cal).note,
       "Since your last block: 31 m of light has passed.")
    eq(g.tally.blocks, 1, "the block itself still counts")

    var long = fresh(at(3, 8))
    let t = pomodoros(&long, 4, from: at(3, 8))
    _ = long.tick(now: t.addingTimeInterval(31 * 60), daylight: sun, calendar: cal)
    check(long.offer == nil && long.pomodorosInCycle == 0, "a long break left waiting closes the cycle")

    var after = fresh(at(3, 10))
    after.start(.pomodoro, now: at(3, 10), daylight: sun, calendar: cal)
    _ = after.tick(now: at(3, 10, 25), daylight: sun, calendar: cal)
    after.acceptOffer(now: at(3, 10, 25), daylight: sun, calendar: cal)
    _ = after.tick(now: at(3, 10, 30), daylight: sun, calendar: cal)
    eq(after.offer?.title, "Start 25 min")
    _ = after.tick(now: at(3, 11, 1), daylight: sun, calendar: cal)
    eq(after.offer, nil, "the next block's offer after a break expires the same way")

    var sunset = fresh(at(3, 17, 30))
    sunset.start(.untilSunset, now: at(3, 17, 30), daylight: sun, calendar: cal)
    _ = sunset.tick(now: at(3, 18), daylight: sun, calendar: cal)
    _ = sunset.tick(now: at(3, 19), daylight: sun, calendar: cal)
    check(sunset.done != nil, "with no offer waiting, what just finished stays")
}

test("a state saved by another version still loads") {
    func decode(_ json: String) -> LightGlass? {
        try? JSONDecoder().decode(LightGlass.self, from: Data(json.utf8))
    }
    let start = at(3, 9).timeIntervalSinceReferenceDate
    let minimal = """
    {"tally":{"day":"2026-10-03","blocks":2},
     "block":{"kind":"focus","preset":"pomodoro","duration":1500,"startedAt":\(start),"endsAt":\(start + 1500)},
     "offer":{"kind":"rest","preset":"pomodoro","minutes":5},
     "aFieldFromTheFuture":true}
    """
    let g = decode(minimal)
    check(g != nil, "a blob missing every defaulted key decodes")
    eq(g?.block?.longRest, false); eq(g?.block?.segments, []); eq(g?.block?.label, "")
    eq(g?.offer?.longRest, false); eq(g?.offer?.title, "Start 5-min break")
    eq(g?.label, ""); eq(g?.pomodorosInCycle, 0); eq(g?.tally.blocks, 2); eq(g?.tally.focusSeconds, 0)
    eq(g?.statusText(now: at(3, 9, 10)), "15:00", "and the block keeps counting")

    let unreadable = """
    {"tally":{"day":"2026-10-03","blocks":3,"focusSeconds":4500,"lightSeconds":4500},
     "block":{"kind":"focus","preset":"aPresetFromTheFuture","duration":1500,"startedAt":\(start)}}
    """
    let u = decode(unreadable)
    eq(u?.block, nil, "a block it can't read is dropped"); eq(u?.tally.blocks, 3, "today's tally survives it")

    var empty = decode("{}")
    check(empty != nil, "an empty object decodes")
    _ = empty?.tick(now: at(3, 9), daylight: sun, calendar: cal)
    eq(empty?.tally.day, "2026-10-03", "with no tally, the first tick starts today's")
}

// MARK: - The app's real sun

// New York, from the app's own SolarMath, as ParagondayController reads it.
var ny = Calendar(identifier: .gregorian)
ny.timeZone = TimeZone(identifier: "America/New_York")!
let nyLat = 40.7128, nyLon = -74.0060

func solar(_ d: Date) -> LightGlass.DaySpan? {
    if case .times(let rise, let set) = SolarMath.sunriseSunset(on: d, latitude: nyLat, longitude: nyLon,
                                                                 timeZone: ny.timeZone) {
        return .init(sunrise: rise, sunset: set)
    }
    return nil
}

func nyAt(_ month: Int, _ day: Int, _ h: Int, _ m: Int = 0) -> Date {
    ny.date(from: DateComponents(year: 2026, month: month, day: day, hour: h, minute: m))!
}

test("Light Glass reads the same Horizon Time as the menu bar") {
    // The window ParagondayController.installLocalWindow builds for `now`, and its daylight(on:) provider.
    struct Window { var todaySunrise, todaySunset, tomorrowSunrise, tomorrowSunset: Date }
    func window(for now: Date) -> Window? {
        guard let t = solar(now), let n = solar(ny.date(byAdding: .day, value: 1, to: now)!) else { return nil }
        return Window(todaySunrise: t.sunrise, todaySunset: t.sunset, tomorrowSunrise: n.sunrise, tomorrowSunset: n.sunset)
    }
    func provider(_ win: Window) -> LightGlass.Daylight {
        { date in
            if ny.isDate(date, inSameDayAs: win.todaySunrise) { return .init(sunrise: win.todaySunrise, sunset: win.todaySunset) }
            if ny.isDate(date, inSameDayAs: win.tomorrowSunrise) { return .init(sunrise: win.tomorrowSunrise, sunset: win.tomorrowSunset) }
            return solar(date)
        }
    }
    // Copied from ParagondayController.computeDisplay, single display; the source check below keeps
    // the copy honest.
    func menuBar(_ now: Date, _ win: Window) -> String {
        func signedHM(seconds: TimeInterval, positive: Bool) -> String {
            let total = Int(abs(seconds.rounded()))
            return String(format: "%@%d:%02d", positive ? "+" : "\u{2212}", total / 3600, (total % 3600) / 60)
        }
        if now < win.todaySunrise {
            return "\(signedHM(seconds: now.timeIntervalSince(win.todaySunrise), positive: false)) tilrise"
        }
        if now >= win.todaySunset {
            return "\(signedHM(seconds: now.timeIntervalSince(win.tomorrowSunrise), positive: false)) tilrise"
        }
        return "\(signedHM(seconds: now.timeIntervalSince(win.todaySunset), positive: false)) tilset"
    }
    let source = (try? String(contentsOfFile: "Paragonday/ParagondayController.swift", encoding: .utf8)) ?? ""
    for line in [
        "return \"\\(signedHM(seconds: now.timeIntervalSince(win.todaySunset), positive: false)) tilset\"",
        "return \"\\(signedHM(seconds: now.timeIntervalSince(win.todaySunrise), positive: false)) tilrise\"",
        "return \"\\(signedHM(seconds: now.timeIntervalSince(win.tomorrowSunrise), positive: false)) tilrise\"",
        "if now < win.todaySunrise { return .beforeSunrise }",
        "if now >= win.todaySunset { return .afterSunset }",
    ] {
        check(source.contains(line), "computeDisplay still reads: \(line)")
    }

    // Every 7 minutes through four days: an ordinary one, the day after, the autumn clock change and midwinter.
    for (month, day) in [(10, 3), (10, 4), (11, 1), (12, 21)] {
        var mismatches: [String] = []
        var seen = 0
        var now = nyAt(month, day, 0)
        let end = ny.date(byAdding: .day, value: 1, to: now)!
        while now < end {
            if let win = window(for: now) {
                let theirs = menuBar(now, win)
                let ours = LightGlass.horizon(at: now, daylight: provider(win), calendar: ny)
                if theirs != ours { mismatches.append("\(now): menu bar \(theirs), Light Glass \(ours)") }
                // The light share's span is the same stretch the menu bar counts down to.
                if let sky = LightGlass.sky(at: now, daylight: provider(win), calendar: ny) {
                    let target = now < win.todaySunrise ? win.todaySunrise
                        : now >= win.todaySunset ? win.tomorrowSunrise : win.todaySunset
                    if sky.end != target { mismatches.append("\(now): sky ends \(sky.end), menu bar counts to \(target)") }
                }
                seen += 1
            }
            now = now.addingTimeInterval(7 * 60)
        }
        check(seen > 200 && mismatches.isEmpty,
              "2026-\(month)-\(day): \(seen) instants, \(mismatches.count) disagree \(mismatches.prefix(3))")
    }
}

test("light counted across a clock change") {
    // 1 November 2026: New York falls back at 2:00, so the civil day is 25 hours long.
    let nov1 = solar(nyAt(11, 1, 12))!
    near(LightGlass.lightSeconds(in: [.init(start: nyAt(11, 1, 10), end: nyAt(11, 1, 10, 25))],
                                 daylight: solar, calendar: ny), 1500, 0.5, "a morning Pomodoro")
    near(LightGlass.lightSeconds(in: [.init(start: nyAt(11, 1, 0), end: nyAt(11, 2, 0))], daylight: solar, calendar: ny),
         nov1.sunset.timeIntervalSince(nov1.sunrise), 0.5, "the whole day holds exactly its daylight")
    let repeatedHour = ny.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 1, minute: 30))!
    eq(LightGlass.lightSeconds(in: [.init(start: repeatedHour, end: repeatedHour.addingTimeInterval(2 * 3600))],
                               daylight: solar, calendar: ny), 0, "the repeated night hour holds none")

    // 8 March 2026: springs forward at 2:00, a 23-hour day.
    let mar8 = solar(nyAt(3, 8, 12))!
    near(LightGlass.lightSeconds(in: [.init(start: nyAt(3, 7, 20), end: nyAt(3, 9, 4))], daylight: solar, calendar: ny),
         mar8.sunset.timeIntervalSince(mar8.sunrise), 0.5, "a stretch across the short day holds that day's light")
    let three = LightGlass.lightSeconds(in: [.init(start: nyAt(3, 7, 0), end: nyAt(3, 10, 0))], daylight: solar, calendar: ny)
    let expected = [nyAt(3, 7, 12), nyAt(3, 8, 12), nyAt(3, 9, 12)].reduce(0.0) { sum, d in
        let s = solar(d)!; return sum + s.sunset.timeIntervalSince(s.sunrise)
    }
    near(three, expected, 0.5, "three days across the change count each day once")
}

print("\n\(passes) checks passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
