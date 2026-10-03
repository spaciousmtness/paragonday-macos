import AppKit
import CoreLocation

// MARK: - Phase

enum SolarPhase {
    case beforeSunrise
    case daytime
    case afterSunset
}

// MARK: - Preferences

enum Prefs {
    static let dualDisplayKey = "ShowDualDisplay"
    static let utcRowKey = "ShowUTCRow"
    static let manualLatKey = "ManualLatitude"
    static let manualLonKey = "ManualLongitude"
    static let manualEnabledKey = "ManualLocationEnabled"
    static let cachedLatKey = "CachedLatitude"
    static let cachedLonKey = "CachedLongitude"
    static let hasCachedLocationKey = "HasCachedLocation"
}

// MARK: - Cached solar window

private struct SolarWindow {
    var todaySunrise: Date
    var todaySunset: Date
    var tomorrowSunrise: Date
    var tomorrowSunset: Date
    var source: String  // "api" or "local"
}

// MARK: - Controller

final class ParagondayController: NSObject, CLLocationManagerDelegate {

    // UI
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var sunriseItem: NSMenuItem!
    private var sunsetItem: NSMenuItem!
    private var locationItem: NSMenuItem!
    private var sourceItem: NSMenuItem!
    private var dualDisplayItem: NSMenuItem!
    private var utcRowToggleItem: NSMenuItem!
    private var utcRowItem: NSMenuItem!

    // Timer
    private var timer: Timer?

    // Location
    private let locationManager = CLLocationManager()
    private var cachedLocation: CLLocationCoordinate2D?
    private var locationStatus: String = "Locating…"

    // Solar
    private let apiClient = SunTimesAPIClient()
    private var solarWindow: SolarWindow?
    private var solarKey: String?  // dayKey + lat + lon
    private var apiInFlight: Bool = false

    // Light Glass: the hourglass focus timer whose sand is daylight.
    private let lightGlass = LightGlassController()

    // MARK: - Lifecycle

    func start() {
        lightGlass.daylight = { [weak self] date in self?.daylight(on: date) }
        lightGlass.onStatusChange = { [weak self] in self?.renderStatus(now: Date()) }

        buildStatusItem()
        buildMenu()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer

        loadInitialLocation()
        update()
        lightGlass.restore()

        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.update()
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lightGlass.stop()
    }

    // MARK: - Status item / menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)
            button.title = "—:— tilset"
        }
    }

    private func buildMenu() {
        menu = NSMenu()
        menu.autoenablesItems = false

        sunriseItem = NSMenuItem(title: "Sunrise: —", action: nil, keyEquivalent: "")
        sunriseItem.isEnabled = false
        menu.addItem(sunriseItem)

        sunsetItem = NSMenuItem(title: "Sunset: —", action: nil, keyEquivalent: "")
        sunsetItem.isEnabled = false
        menu.addItem(sunsetItem)

        locationItem = NSMenuItem(title: "Location: locating…",
                                  action: nil, keyEquivalent: "")
        locationItem.isEnabled = false
        menu.addItem(locationItem)

        sourceItem = NSMenuItem(title: "Source: —", action: nil, keyEquivalent: "")
        sourceItem.isEnabled = false
        menu.addItem(sourceItem)

        menu.addItem(.separator())

        lightGlass.attach(to: menu, statusItem: statusItem)

        menu.addItem(.separator())

        dualDisplayItem = NSMenuItem(title: "Show dual display",
                                     action: #selector(toggleDualDisplay),
                                     keyEquivalent: "")
        dualDisplayItem.target = self
        dualDisplayItem.state = UserDefaults.standard.bool(forKey: Prefs.dualDisplayKey) ? .on : .off
        menu.addItem(dualDisplayItem)

        utcRowToggleItem = NSMenuItem(title: "Show UTC time",
                                      action: #selector(toggleUTCRow),
                                      keyEquivalent: "")
        utcRowToggleItem.target = self
        utcRowToggleItem.state = UserDefaults.standard.bool(forKey: Prefs.utcRowKey) ? .on : .off
        menu.addItem(utcRowToggleItem)

        utcRowItem = NSMenuItem(title: "UTC: —", action: nil, keyEquivalent: "")
        utcRowItem.isEnabled = false
        utcRowItem.isHidden = !UserDefaults.standard.bool(forKey: Prefs.utcRowKey)
        menu.addItem(utcRowItem)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh location",
                                     action: #selector(refreshLocation),
                                     keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let manualItem = NSMenuItem(title: "Use manual location…",
                                    action: #selector(showManualLocationSheet),
                                    keyEquivalent: "")
        manualItem.target = self
        menu.addItem(manualItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About Paragonday",
                                   action: #selector(showAbout),
                                   keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit Paragonday",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Location

    private func loadInitialLocation() {
        let defaults = UserDefaults.standard

        // Manual location wins.
        if defaults.bool(forKey: Prefs.manualEnabledKey) {
            let lat = defaults.double(forKey: Prefs.manualLatKey)
            let lon = defaults.double(forKey: Prefs.manualLonKey)
            cachedLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            locationStatus = String(format: "Manual: %.4f, %.4f", lat, lon)
            return
        }

        // Use last cached location if we have one — survives TCC permission resets.
        if defaults.bool(forKey: Prefs.hasCachedLocationKey) {
            let lat = defaults.double(forKey: Prefs.cachedLatKey)
            let lon = defaults.double(forKey: Prefs.cachedLonKey)
            cachedLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            locationStatus = String(format: "%.4f, %.4f (cached)", lat, lon)
            return
        }

        requestSystemLocation()
    }

    private func requestSystemLocation() {
        let status = locationManager.authorizationStatus
        FileHandle.standardError.write(Data("[Paragonday] requestSystemLocation auth=\(status.rawValue)\n".utf8))
        switch status {
        case .notDetermined:
            locationStatus = "Awaiting permission…"
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            locationManager.requestWhenInUseAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                NSApp.setActivationPolicy(.accessory)
            }
        case .denied, .restricted:
            locationStatus = "Location denied — enable in System Settings"
            cachedLocation = nil
        case .authorizedAlways, .authorized:
            locationStatus = "Locating…"
            locationManager.requestLocation()
        @unknown default:
            locationStatus = "Locating…"
            locationManager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorized:
            locationStatus = "Locating…"
            manager.requestLocation()
        case .denied, .restricted:
            // If we have a cached location, keep using it; otherwise show error.
            if cachedLocation == nil {
                locationStatus = "Location denied — enable in System Settings"
            }
            update()
        case .notDetermined:
            locationStatus = "Awaiting permission…"
        @unknown default: break
        }
        update()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        cachedLocation = loc.coordinate
        locationStatus = String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude)

        // Persist so a TCC reset on next launch doesn't break the app.
        let defaults = UserDefaults.standard
        defaults.set(loc.coordinate.latitude, forKey: Prefs.cachedLatKey)
        defaults.set(loc.coordinate.longitude, forKey: Prefs.cachedLonKey)
        defaults.set(true, forKey: Prefs.hasCachedLocationKey)

        manager.stopUpdatingLocation()
        solarKey = nil
        update()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Don't override status if we have a cached location.
        if cachedLocation == nil {
            locationStatus = "Location error: \(error.localizedDescription)"
        }
        update()
    }

    // MARK: - Update loop

    private func update() {
        let now = Date()

        let coord = currentCoord()

        if let coord = coord {
            ensureSolarWindow(for: now, coord: coord)
        }

        sunriseItem.title = "Sunrise: \(formatTime(solarWindow?.todaySunrise))"
        sunsetItem.title = "Sunset: \(formatTime(solarWindow?.todaySunset))"
        locationItem.title = "Location: \(locationStatus)"
        sourceItem.title = "Source: \(solarWindow?.source ?? "—")"

        // Allow clicking the location row to open Settings if denied AND we have no cached fix.
        if cachedLocation == nil,
           !UserDefaults.standard.bool(forKey: Prefs.manualEnabledKey),
           locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
            locationItem.action = #selector(openLocationSettings)
            locationItem.target = self
            locationItem.isEnabled = true
        } else {
            locationItem.action = nil
            locationItem.isEnabled = false
        }

        utcRowItem.isHidden = !UserDefaults.standard.bool(forKey: Prefs.utcRowKey)
        if !utcRowItem.isHidden {
            utcRowItem.title = LightGlass.utcRow(now)   // hours and minutes: Paragonday never shows seconds
        }

        let display = computeDisplay(now: now, coord: coord)
        lightGlass.heartbeat()
        renderStatus(now: now, display: display)

        let lat = coord?.latitude.description ?? "nil"
        let lon = coord?.longitude.description ?? "nil"
        let phase = currentPhase(now: now)
        let ts = ISO8601DateFormatter().string(from: now)
        let auth = locationManager.authorizationStatus.rawValue
        let src = solarWindow?.source ?? "none"
        FileHandle.standardError.write(
            Data("[Paragonday] \(ts) auth=\(auth) lat=\(lat) lon=\(lon) phase=\(String(describing: phase)) src=\(src) display=\(display)\n".utf8)
        )
    }

    private func currentCoord() -> CLLocationCoordinate2D? {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Prefs.manualEnabledKey) {
            return CLLocationCoordinate2D(latitude: defaults.double(forKey: Prefs.manualLatKey),
                                          longitude: defaults.double(forKey: Prefs.manualLonKey))
        }
        return cachedLocation
    }

    /// The status item: Horizon Time, or while a Light Glass block runs, an hourglass and its time left.
    private func renderStatus(now: Date, display: String? = nil) {
        guard let button = statusItem.button else { return }
        let look = lightGlass.statusLook(now: now)
        button.title = look.title ?? display ?? computeDisplay(now: now, coord: currentCoord())
        if let name = look.symbol, let image = hourglassImage(name) {
            if button.image !== image { button.image = image }
            button.imagePosition = .imageLeading
        } else if button.image != nil {
            button.image = nil
        }
    }

    /// The three hourglass glyphs, made once: this runs every second while a block counts down.
    private var hourglassImages: [String: NSImage] = [:]

    private func hourglassImage(_ name: String) -> NSImage? {
        if let cached = hourglassImages[name] { return cached }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: "Light Glass")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)) else { return nil }
        image.isTemplate = true
        hourglassImages[name] = image
        return image
    }

    /// Sunrise and sunset for the civil day containing `date`, for Light Glass: the cached window
    /// (API-refined) for today and tomorrow, SolarMath for any other day. Nil without a location or
    /// in polar day/night.
    private func daylight(on date: Date) -> LightGlass.DaySpan? {
        let cal = Calendar.current
        if let win = solarWindow {
            if cal.isDate(date, inSameDayAs: win.todaySunrise) {
                return LightGlass.DaySpan(sunrise: win.todaySunrise, sunset: win.todaySunset)
            }
            if cal.isDate(date, inSameDayAs: win.tomorrowSunrise) {
                return LightGlass.DaySpan(sunrise: win.tomorrowSunrise, sunset: win.tomorrowSunset)
            }
        }
        guard let coord = currentCoord(), abs(coord.latitude) <= SolarMath.polarLatitudeDegrees else { return nil }
        if case .times(let rise, let set) = SolarMath.sunriseSunset(on: date,
                                                                     latitude: coord.latitude,
                                                                     longitude: coord.longitude) {
            return LightGlass.DaySpan(sunrise: rise, sunset: set)
        }
        return nil
    }

    // MARK: - Solar cache

    private func ensureSolarWindow(for now: Date, coord: CLLocationCoordinate2D) {
        let key = solarCacheKey(for: now, lat: coord.latitude, lon: coord.longitude)
        if key == solarKey, solarWindow != nil { return }
        solarKey = key

        // Synchronous local fallback gets us something on screen immediately.
        installLocalWindow(for: now, coord: coord)

        // Refine via API, async.
        guard !apiInFlight else { return }
        apiInFlight = true
        apiClient.fetch(latitude: coord.latitude, longitude: coord.longitude) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.apiInFlight = false
                switch result {
                case .success(let win):
                    self.solarWindow = SolarWindow(
                        todaySunrise: win.todaySunrise,
                        todaySunset: win.todaySunset,
                        tomorrowSunrise: win.tomorrowSunrise,
                        tomorrowSunset: win.tomorrowSunset,
                        source: "api"
                    )
                    self.update()
                case .failure(let err):
                    FileHandle.standardError.write(
                        Data("[Paragonday] API error: \(err.localizedDescription)\n".utf8)
                    )
                    // Keep the local window in place.
                }
            }
        }
    }

    private func installLocalWindow(for now: Date, coord: CLLocationCoordinate2D) {
        if abs(coord.latitude) > SolarMath.polarLatitudeDegrees {
            solarWindow = nil
            return
        }
        let cal = Calendar(identifier: .gregorian)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now

        let today = SolarMath.sunriseSunset(on: now,
                                            latitude: coord.latitude,
                                            longitude: coord.longitude)
        let next = SolarMath.sunriseSunset(on: tomorrow,
                                           latitude: coord.latitude,
                                           longitude: coord.longitude)

        if case .times(let tRise, let tSet) = today,
           case .times(let nRise, let nSet) = next {
            solarWindow = SolarWindow(
                todaySunrise: tRise,
                todaySunset: tSet,
                tomorrowSunrise: nRise,
                tomorrowSunset: nSet,
                source: "local"
            )
        } else {
            solarWindow = nil
        }
    }

    private func solarCacheKey(for date: Date, lat: Double, lon: Double) -> String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)|\(lat)|\(lon)"
    }

    // MARK: - Phase + display

    private func currentPhase(now: Date) -> SolarPhase? {
        guard let win = solarWindow else { return nil }
        if now < win.todaySunrise { return .beforeSunrise }
        if now >= win.todaySunset { return .afterSunset }
        return .daytime
    }

    private func computeDisplay(now: Date, coord: CLLocationCoordinate2D?) -> String {
        if coord == nil { return "—:— tilset" }
        guard let win = solarWindow, let phase = currentPhase(now: now) else {
            return "—:— tilset"
        }

        let dual = UserDefaults.standard.bool(forKey: Prefs.dualDisplayKey)
        if dual {
            let pastRise = signedHM(seconds: now.timeIntervalSince(win.todaySunrise), positive: true)
            let tilSet = signedHM(seconds: now.timeIntervalSince(win.todaySunset), positive: false)
            return "\(pastRise) / \(tilSet)"
        }

        switch phase {
        case .daytime:
            return "\(signedHM(seconds: now.timeIntervalSince(win.todaySunset), positive: false)) tilset"
        case .beforeSunrise:
            return "\(signedHM(seconds: now.timeIntervalSince(win.todaySunrise), positive: false)) tilrise"
        case .afterSunset:
            return "\(signedHM(seconds: now.timeIntervalSince(win.tomorrowSunrise), positive: false)) tilrise"
        }
    }

    /// Format seconds as "+H:MM" or "−H:MM" (Unicode minus).
    private func signedHM(seconds: TimeInterval, positive: Bool) -> String {
        let total = Int(abs(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let sign = positive ? "+" : "\u{2212}"
        return String(format: "%@%d:%02d", sign, h, m)
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    // MARK: - Menu actions

    @objc private func toggleDualDisplay() {
        let cur = UserDefaults.standard.bool(forKey: Prefs.dualDisplayKey)
        UserDefaults.standard.set(!cur, forKey: Prefs.dualDisplayKey)
        dualDisplayItem.state = !cur ? .on : .off
        update()
    }

    @objc private func toggleUTCRow() {
        let cur = UserDefaults.standard.bool(forKey: Prefs.utcRowKey)
        UserDefaults.standard.set(!cur, forKey: Prefs.utcRowKey)
        utcRowToggleItem.state = !cur ? .on : .off
        update()
    }

    @objc private func refreshLocation() {
        UserDefaults.standard.set(false, forKey: Prefs.manualEnabledKey)
        // Don't clear the cached location — if CoreLocation fails, fall back to it.
        solarKey = nil
        requestSystemLocation()
        update()
    }

    @objc private func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showManualLocationSheet() {
        let alert = NSAlert()
        alert.messageText = "Manual location"
        alert.informativeText = "Enter latitude and longitude in decimal degrees (e.g. 37.7749, -122.4194). Leave blank to clear and resume system location."
        alert.alertStyle = .informational

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 260, height: 60))
        stack.orientation = .vertical
        stack.spacing = 6

        let latField = NSTextField(string: "")
        latField.placeholderString = "Latitude"
        let lonField = NSTextField(string: "")
        lonField.placeholderString = "Longitude"

        if UserDefaults.standard.bool(forKey: Prefs.manualEnabledKey) {
            latField.stringValue = String(UserDefaults.standard.double(forKey: Prefs.manualLatKey))
            lonField.stringValue = String(UserDefaults.standard.double(forKey: Prefs.manualLonKey))
        }

        stack.addArrangedSubview(latField)
        stack.addArrangedSubview(lonField)
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 56)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let latStr = latField.stringValue.trimmingCharacters(in: .whitespaces)
        let lonStr = lonField.stringValue.trimmingCharacters(in: .whitespaces)

        if latStr.isEmpty && lonStr.isEmpty {
            UserDefaults.standard.set(false, forKey: Prefs.manualEnabledKey)
            requestSystemLocation()
            solarKey = nil
            update()
            return
        }

        guard let lat = Double(latStr), let lon = Double(lonStr),
              lat >= -90, lat <= 90, lon >= -180, lon <= 180 else {
            let err = NSAlert()
            err.messageText = "Invalid coordinates"
            err.informativeText = "Latitude must be between -90 and 90, longitude between -180 and 180."
            err.runModal()
            return
        }

        UserDefaults.standard.set(lat, forKey: Prefs.manualLatKey)
        UserDefaults.standard.set(lon, forKey: Prefs.manualLonKey)
        UserDefaults.standard.set(true, forKey: Prefs.manualEnabledKey)
        cachedLocation = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        locationStatus = String(format: "Manual: %.4f, %.4f", lat, lon)
        solarKey = nil
        update()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Paragonday"
        alert.informativeText = "Solar-relative time in your menu bar.\n\nUses the Paragonday API for sunrise/sunset, with a local fallback when offline.\n\nLight Glass is an hourglass focus timer whose sand is daylight."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
