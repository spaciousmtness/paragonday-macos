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
- **Light Glass**: an hourglass focus timer whose sand is daylight (below)

## Light Glass

A focus timer that counts in light. Its hourglass holds what is left of today's daylight; at night it holds the night until sunrise, in starlit blue, and the menu says `tilrise`.

- **Blocks**: Start Pomodoro (25 minutes, then a 5-minute break; a 15-minute break after the fourth), Focus 50 (10-minute break), Deep 90 (20-minute break), Until sunset (until sunrise at night), or a custom length (its break is a fifth of it)
- **What's next?**: a few words for the block, shown in the menu and under the hourglass
- **While a block runs** the menu bar shows an hourglass and the time left (`18:42`); the menu shows the Horizon Time it will be when the block ends (`ends at −4:47 tilset`), and a gentle warning if it runs past sunset. Left-click opens the hourglass, right-click (or control-click) the menu. When no block runs, the menu bar is plain Horizon Time, as before
- **The hourglass**: the top bulb is the light still to come, the block's minutes are its top layer (a dashed line marks where the sand will stand when the block ends), the light already passed lies in the bottom bulb, and every finished block rests there as a small sun
- **At the end of a block** a soft bell rings (synthesised in the app; a nod to Brenda Hutchinson's dailybell, which rings bells at sunrise and sunset) and a notification offers the break, which starts on a click
- **When idle**, the line under the glass says how much light has passed since your last block
- **Today**: blocks done and light spent (`4 blocks · 1 h 40 m of light`), saved with the running block so quitting and relaunching carries on where it was

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

### Without Xcode (Command Line Tools only)

```sh
scripts/build-cli.sh              # compiles with swiftc, assembles and ad-hoc signs build/cli/Paragonday.app
open build/cli/Paragonday.app

scripts/test-lightglass.sh        # Light Glass logic tests, then an offscreen click-through of its menu
scripts/render-lightglass.sh      # renders the hourglass (day, mid-block, past sunset, break, night) to build/renders/
```

## How it works

The app is a small AppKit menu-bar agent (no Dock icon) in plain Swift — no dependencies:

| File | Role |
|------|------|
| `ParagondayController.swift` | Status item, menu, location handling, display logic |
| `APIClient.swift` | Fetches the sunrise/sunset window from the Paragonday API |
| `SolarMath.swift` | Offline sunrise/sunset calculation (SunCalc port) |
| `LightGlass.swift` | Light Glass rules: block state machine, light-share maths, today's tally, saving (Foundation only, tested) |
| `LightGlassController.swift` | Light Glass in the app: menu section, menu-bar countdown, popover, notifications |
| `LightGlassView.swift` | The hourglass, in SwiftUI |
| `LightGlassBell.swift` | The bell, synthesised as a WAV |

Above the polar circle (|lat| > 66.56°) during polar day/night the local fallback reports no sunrise/sunset and the display shows `—:— tilset`.

## Related

- [paragonday-ios](https://github.com/tealprocess/paragonday-ios) — the iOS app
- [Paragonday Systems](https://paragonday.systems) — the Horizon Time framework

## License

[MIT](LICENSE)
