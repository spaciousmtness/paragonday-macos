import AppKit
import SwiftUI

// Renders the Light Glass view to PNGs without launching the app, so the hourglass can be looked at
// (and reviewed) from the command line. Run with scripts/render-lightglass.sh [output-dir].
//
// The sky is New York on 3 October 2026, from the app's own SolarMath.

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/renders"
let prefix = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "lightglass-"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "America/New_York")!
let lat = 40.7128, lon = -74.0060

let daylight: LightGlass.Daylight = { d in
    if case .times(let rise, let set) = SolarMath.sunriseSunset(on: d, latitude: lat, longitude: lon,
                                                                 timeZone: cal.timeZone) {
        return .init(sunrise: rise, sunset: set)
    }
    return nil
}

func at(_ h: Int, _ m: Int) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: h, minute: m))!
}

/// Pomodoros finished back to back from a starting time, the way a morning would leave the tally.
func finishPomodoros(_ g: inout LightGlass, count: Int, from h: Int, _ m: Int) {
    var t = at(h, m)
    for _ in 0..<count {
        g.start(.pomodoro, now: t, daylight: daylight, calendar: cal)
        t = g.block!.endsAt!
        _ = g.tick(now: t, daylight: daylight, calendar: cal)
        t = t.addingTimeInterval(5 * 60)
    }
    g.stop()   // skip the last break offer so the scene is idle
}

struct Scene {
    let name: String
    let now: Date
    let build: (inout LightGlass) -> Void
}

let scenes: [Scene] = [
    Scene(name: "idle-day", now: at(14, 20)) { g in
        finishPomodoros(&g, count: 2, from: 10, 0)
        g.setLabel("Draft the dailybell note")
    },
    Scene(name: "mid-block", now: at(15, 5)) { g in
        finishPomodoros(&g, count: 3, from: 10, 0)
        g.setLabel("Draft the dailybell note")
        g.start(.pomodoro, now: at(14, 55), daylight: daylight, calendar: cal)
    },
    Scene(name: "until-sunset", now: at(11, 52)) { g in
        finishPomodoros(&g, count: 1, from: 10, 0)
        g.start(.untilSunset, now: at(11, 51), daylight: daylight, calendar: cal)
    },
    Scene(name: "past-sunset", now: at(17, 55)) { g in
        finishPomodoros(&g, count: 3, from: 10, 0)
        g.setLabel("Edit the proposal")
        g.start(.deep90, now: at(17, 50), daylight: daylight, calendar: cal)
    },
    Scene(name: "break-ready", now: at(16, 1)) { g in
        finishPomodoros(&g, count: 3, from: 10, 0)
        g.setLabel("Venue shortlist")
        g.start(.pomodoro, now: at(15, 35), daylight: daylight, calendar: cal)
        _ = g.tick(now: at(16, 0), daylight: daylight, calendar: cal)
    },
    Scene(name: "night", now: at(21, 40)) { g in
        finishPomodoros(&g, count: 4, from: 10, 0)
    },
    Scene(name: "morning", now: at(8, 10)) { _ in },
    Scene(name: "finished-blocks", now: at(16, 40)) { g in
        finishPomodoros(&g, count: 7, from: 9, 0)
        g.setLabel("Invitation copy")
    },
    Scene(name: "night-running", now: at(20, 40)) { g in
        finishPomodoros(&g, count: 4, from: 10, 0)
        g.setLabel("Bell research")
        g.start(.pomodoro, now: at(20, 31), daylight: daylight, calendar: cal)
    },
]

MainActor.assumeIsolated {
    for scene in scenes {
        var g = LightGlass(now: at(0, 1), calendar: cal)
        scene.build(&g)
        _ = g.tick(now: scene.now, daylight: daylight, calendar: cal)
        let snap = g.snapshot(now: scene.now, daylight: daylight, calendar: cal)
        let renderer = ImageRenderer(content: LightGlassView(snap: snap, actions: LightGlassActions()))
        renderer.scale = 2
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("could not render \(scene.name)\n".utf8))
            exit(1)
        }
        let path = (outDir as NSString).appendingPathComponent("\(prefix)\(scene.name).png")
        try! png.write(to: URL(fileURLWithPath: path))
        print("\(path)  \(cg.width)×\(cg.height)  \(snap.horizonNow)  top \(String(format: "%.2f", snap.topShare))  \(snap.todayLine)")
    }
}
