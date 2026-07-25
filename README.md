# Paragonday for macOS

Solar-relative time in your menu bar. **[Website](https://tealprocess.github.io/paragonday-macos/)** · **[Download](../../releases/latest)**

Paragonday replaces the clock question "what time is it?" with the one your body actually asks: **how much daylight is left?** It lives in the macOS menu bar and shows [Horizon Time](https://paragonday.systems) — time measured relative to sunrise and sunset at your location:

- During the day: `−2:41 tilset` — 2 h 41 m until sunset
- Before sunrise / after sunset: `−7:12 tilrise` — 7 h 12 m until the next sunrise

## Features

- **Menu bar display** of time until sunset (`tilset`) or the next sunrise (`tilrise`), updated continuously
- **Dual display** mode: time since sunrise and until sunset at once (`+5:03 / −2:41`)
- **Optional UTC row** in the dropdown for coordinating across horizons
- **Automatic location** via macOS Location Services, with the last fix cached so the app keeps working across permission resets
- **Manual location** — enter any latitude/longitude to see Horizon Time somewhere else
- **Online + offline**: sunrise/sunset comes from the Paragonday API when reachable, with a built-in astronomical fallback (a Swift port of [SunCalc](https://github.com/mourner/suncalc)'s Meeus-derived algorithm, ~±1 minute) when offline

## Install

1. Download `Paragonday.app.zip` from the [latest release](../../releases/latest)
2. Unzip and drag `Paragonday.app` into your Applications folder
3. First launch: **right-click the app → Open → Open**. The app is not notarized yet, so macOS will warn on a normal double-click
4. Grant location access when prompted (used only to compute sunrise/sunset), or pick **Use manual location…** from the menu

Requires macOS 14.0 or later. The release build is Apple Silicon (arm64); Intel Macs can build from source.

## Build from source

```sh
git clone https://github.com/tealprocess/paragonday-macos.git
cd paragonday-macos
open Paragonday.xcodeproj   # then Product → Run
```

or from the command line:

```sh
xcodebuild -project Paragonday.xcodeproj -scheme Paragonday -configuration Release build
```

## How it works

The app is a small AppKit menu-bar agent (no Dock icon) in plain Swift — no dependencies:

| File | Role |
|------|------|
| `ParagondayController.swift` | Status item, menu, location handling, display logic |
| `APIClient.swift` | Fetches the sunrise/sunset window from the Paragonday API |
| `SolarMath.swift` | Offline sunrise/sunset calculation (SunCalc port) |

Above the polar circle (|lat| > 66.56°) during polar day/night the local fallback reports no sunrise/sunset and the display shows `—:— tilset`.

## Related

- [paragonday-ios](https://github.com/tealprocess/paragonday-ios) — the iOS app
- [Paragonday Systems](https://paragonday.systems) — the Horizon Time framework

## License

[MIT](LICENSE)
