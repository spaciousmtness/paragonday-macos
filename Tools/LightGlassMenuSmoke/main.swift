import AppKit

// Clicks through the Light Glass menu section offscreen: a plain NSMenu, no status item, no app
// launched, nothing in the menu bar. Checks the AppKit wiring the logic tests can't reach (items
// appear, their actions fire, state is saved). Run with scripts/test-lightglass.sh.

var failures = 0
func check(_ cond: Bool, _ msg: String) {
    print(cond ? "ok    \(msg)" : "FAIL  \(msg)")
    if !cond { failures += 1 }
}

let suite = "LightGlassMenuSmoke-\(ProcessInfo.processInfo.processIdentifier)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }

// A sky where it is always mid-afternoon: sunset four hours from whenever this runs.
let launched = Date()
let daylight: LightGlass.Daylight = { d in
    let shift = Calendar.current.startOfDay(for: d).timeIntervalSince(Calendar.current.startOfDay(for: launched))
    return .init(sunrise: launched.addingTimeInterval(shift - 3 * 3600),
                 sunset: launched.addingTimeInterval(shift + 4 * 3600))
}

let controller = LightGlassController(defaults: defaults)
controller.daylight = daylight
var redraws = 0
controller.onStatusChange = { redraws += 1 }

let menu = NSMenu()
menu.autoenablesItems = false
menu.addItem(NSMenuItem(title: "Sunrise: 7:01 AM", action: nil, keyEquivalent: ""))
menu.addItem(.separator())
controller.attach(to: menu, statusItem: nil)
menu.addItem(.separator())
menu.addItem(NSMenuItem(title: "Quit Paragonday", action: nil, keyEquivalent: "q"))

func titles() -> [String] { menu.items.map { $0.isSeparatorItem ? "—" : $0.title } }
func click(_ prefix: String) -> Bool {
    guard let i = menu.items.firstIndex(where: { $0.title.hasPrefix(prefix) && $0.isEnabled && $0.action != nil }) else {
        print("  no enabled item starting \"\(prefix)\" in \(titles())")
        return false
    }
    // No NSApplication here (making one could put an icon in the Dock), and NSMenu routes a click
    // through NSApp; so send the item's action to its target the way NSApp would.
    let item = menu.items[i]
    guard let target = item.target as? NSObject, let action = item.action else {
        print("  \"\(prefix)\" has no target/action")
        return false
    }
    target.perform(action, with: item)
    return true
}
print("NSApp in this process: \(NSApp == nil ? "none" : "present")")

print("idle:     \(titles())")
check(titles().contains("Light Glass"), "section header is in the menu")
check(titles().contains("Start Pomodoro") && titles().contains("Focus 50") && titles().contains("Deep 90"), "presets offered")
check(titles().contains(where: { $0.hasPrefix("Until sunset (3 h 59 m)") || $0.hasPrefix("Until sunset (4 h)") }), "until sunset shows its length")
check(titles().contains("No blocks yet today"), "today line")
check(titles().last == "Quit Paragonday" && titles().first == "Sunrise: 7:01 AM", "the app's own items keep their places")
check(controller.statusLook(now: Date()).title == nil, "idle: the menu bar keeps Horizon Time")

check(click("Start Pomodoro"), "click Start Pomodoro")
print("running:  \(titles())")
check(titles().contains(where: { $0.hasPrefix("Pomodoro · 25:00 left") || $0.hasPrefix("Pomodoro · 24:59 left") }), "countdown line")
check(titles().contains(where: { $0.hasPrefix("ends at −") && $0.hasSuffix("tilset") }), "ends-at Horizon Time")
check(titles().contains("Pause") && titles().contains("Stop") && !titles().contains("Start Pomodoro"), "running controls replace the presets")
let look = controller.statusLook(now: Date())
check((look.title == "25:00" || look.title == "24:59") && look.symbol == "hourglass.bottomhalf.filled", "menu bar shows an hourglass and the time left")
check(defaults.data(forKey: LightGlass.Keys.state) != nil, "state saved for a relaunch")
check(redraws > 0, "status item asked to redraw")

// A relaunch, at the controller: a second one built from the same saved state, as the app would at launch.
let relaunched = LightGlassController(defaults: defaults)
relaunched.daylight = daylight
relaunched.restore()
let relook = relaunched.statusLook(now: Date())
check(relook.symbol == "hourglass.bottomhalf.filled"
        && ["25:00", "24:59", "24:58"].contains(relook.title ?? ""),
      "after a relaunch the menu bar carries on counting down (\(relook.title ?? "nil"))")
check(relaunched.glass.block?.preset == .pomodoro, "the relaunched controller holds the same block")
relaunched.stop()

check(click("Pause"), "click Pause")
check(titles().contains("Resume"), "paused: Resume offered")
check(controller.statusLook(now: Date()).title?.hasSuffix("paused") == true, "menu bar says paused")
let restored = LightGlass.load(from: defaults, now: Date())
check(restored.block?.isPaused == true, "pause survives a relaunch")

check(click("Resume"), "click Resume")
check(click("Stop"), "click Stop")
print("stopped:  \(titles())")
check(titles().contains("Start Pomodoro") && controller.glass.block == nil, "back to idle")
check(controller.glass.tally.blocks == 0, "a stopped block isn't counted")

check(click("Deep 90"), "click Deep 90")
check(controller.glass.block?.duration == 90 * 60, "Deep 90 is ninety minutes")
check(click("Stop"), "stop it")

print("\(failures == 0 ? "menu smoke passed" : "menu smoke FAILED (\(failures))")")
exit(failures == 0 ? 0 : 1)
