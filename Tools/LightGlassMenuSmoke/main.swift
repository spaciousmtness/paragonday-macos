import AppKit
import SwiftUI

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
check(titles().contains("Pomodoro · 0:25 left"), "countdown line, hours and minutes")
check(titles().contains(where: { $0.hasPrefix("ends −") && $0.hasSuffix(" TS") }), "ends-at Horizon Time, in the Sun Dial's shorthand")
check(titles().contains("Pause") && titles().contains("Stop") && !titles().contains("Start Pomodoro"), "running controls replace the presets")
let look = controller.statusLook(now: Date())
check(look.title == "0:25" && look.symbol == "hourglass.bottomhalf.filled", "menu bar shows an hourglass and the time left, no seconds")
check(defaults.data(forKey: LightGlass.Keys.state) != nil, "state saved for a relaunch")
check(redraws > 0, "status item asked to redraw")

// A relaunch, at the controller: a second one built from the same saved state, as the app would at launch.
let relaunched = LightGlassController(defaults: defaults)
relaunched.daylight = daylight
relaunched.restore()
let relook = relaunched.statusLook(now: Date())
check(relook.symbol == "hourglass.bottomhalf.filled" && relook.title == "0:25",
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

// The teal accent: Paragonday's mark beside the panel's name, teal on the primary button; the sand stays gold.
func hex(_ c: Color) -> String {
    guard let n = NSColor(c).usingColorSpace(.sRGB) else { return "?" }
    return String(format: "#%02X%02X%02X", Int((n.redComponent * 255).rounded()),
                  Int((n.greenComponent * 255).rounded()), Int((n.blueComponent * 255).rounded()))
}
check(hex(LightGlassPalette.day.button) == "#008080", "primary button is teal by day (\(hex(LightGlassPalette.day.button)))")
check(hex(LightGlassPalette.night.button) == "#169F9F", "and the lighter teal by night (\(hex(LightGlassPalette.night.button)))")
check(hex(LightGlassPalette.day.brandMark) == "#417B7D" && hex(LightGlassPalette.night.brandMark) == "#417B7D",
      "the Paragonday mark in its own teal")
check(hex(LightGlassPalette.day.sand[0]) == "#EEAE45" && hex(LightGlassPalette.day.stream) == "#CF7A28",
      "the sunlight sand stays gold (the Melting Glass sun and its shadow side)")

// The Melting Glass painting, rendered offscreen: gold sand under a dusk sky by day, starlit sand under
// a dark sky by night, and a panel short enough for a small screen's popover.
MainActor.assumeIsolated {
    let w: CGFloat = LightGlassView.paintingWidth, crop = MeltingGlassPainting.crop
    let k = w / crop.width
    @MainActor func pixel(_ snap: LightGlass.Snapshot, _ x: CGFloat, _ y: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        let r = ImageRenderer(content: MeltingGlassPainting(scene: MeltScene(snap))
            .frame(width: w, height: MeltingGlassPainting.height(forWidth: w)))
        r.scale = 1
        guard let cg = r.cgImage, let c = NSBitmapImageRep(cgImage: cg)
            .colorAt(x: Int((x - crop.minX) * k), y: Int((y - crop.minY) * k))?.usingColorSpace(.sRGB) else { return nil }
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }
    /// A point well inside the top bulb's sand, below the next block's pale layer.
    @MainActor func inSand(_ snap: LightGlass.Snapshot) -> (CGFloat, CGFloat) {
        let scene = MeltScene(snap), glass = MeltGlass(melt: scene.melt)
        let yS = glass.levelY(scene.share), y = yS + 0.7 * (MeltGlass.yNeck - 12 - yS)
        return (glass.midI(y) - 6, y)
    }
    var g = LightGlass(now: launched)
    let daySnap = g.snapshot(now: launched, daylight: daylight)
    let sand = pixel(daySnap, inSand(daySnap).0, inSand(daySnap).1), sky = pixel(daySnap, 60, 60)
    check(sand.map { $0.r > 0.7 && $0.r > $0.g && $0.g > $0.b } ?? false, "painting: gold sand by day \(String(describing: sand))")
    check(sky.map { $0.b > $0.r } ?? false, "painting: a blue-grey sky at the top by day \(String(describing: sky))")
    let nightNow = launched.addingTimeInterval(7 * 3600)   // three hours after this sky's sunset
    _ = g.tick(now: nightNow, daylight: daylight)
    let nightSnap = g.snapshot(now: nightNow, daylight: daylight)
    let nSand = pixel(nightSnap, inSand(nightSnap).0, inSand(nightSnap).1), nSky = pixel(nightSnap, 60, 60)
    check(nightSnap.phase == .night && (nSand.map { $0.b > $0.r } ?? false), "painting: starlit sand by night \(String(describing: nSand))")
    check(nSky.map { $0.r + $0.g + $0.b < 0.75 } ?? false, "painting: the same drawing, dark, by night \(String(describing: nSky))")
    let unknown = LightGlass(now: launched).snapshot(now: launched, daylight: { _ in nil })
    check(unknown.phase == nil && pixel(unknown, 60, 60) != nil, "painting: draws with the sky unknown (no location yet)")
    let panel = ImageRenderer(content: LightGlassView(snap: daySnap, actions: LightGlassActions()))
    let size = panel.cgImage.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
    check(size.width == 300 && size.height > 0 && size.height <= 720, "panel stays 300 pt wide and fits a small screen (\(size))")
}

print("\(failures == 0 ? "menu smoke passed" : "menu smoke FAILED (\(failures))")")
exit(failures == 0 ? 0 : 1)
