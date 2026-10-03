import AppKit
import SwiftUI
import UserNotifications

/// Light Glass inside the app: its menu section, the menu-bar countdown, the hourglass popover, the
/// bell and the notification. The timer's rules live in LightGlass.swift; this file wires them to AppKit.
final class LightGlassController: NSObject, NSMenuDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {

    /// Sun times for the civil day containing a date. ParagondayController supplies it from its solar
    /// window and SolarMath, so Light Glass reads the same sun as the menu bar.
    var daylight: LightGlass.Daylight = { _ in nil }
    /// Asks ParagondayController to redraw the status item (once a second while a block runs).
    var onStatusChange: () -> Void = {}

    private(set) var glass: LightGlass
    private let defaults: UserDefaults
    private weak var statusItem: NSStatusItem?
    private weak var menu: NSMenu?
    private var header: NSMenuItem?
    private var sectionItems: [NSMenuItem] = []
    private var ticker: Timer?
    private var popover: NSPopover?
    private var model: LightGlassModel?
    private lazy var bell: NSSound? = {
        let sound = NSSound(data: LightGlassBell.wav())
        sound?.volume = 0.7
        return sound
    }()
    private var askedForNotifications = false
    /// Held while a block runs, so App Nap doesn't throttle the once-a-second countdown.
    private var activity: NSObjectProtocol?
    /// When the popover last began closing. A transient popover closes on the mouse-down of a click
    /// on the status item, and the mouse-up that follows must not open it again.
    private var popoverClosedAt: Date?

    private static let offerCategory = "lightglass.offer"
    private static let acceptAction = "lightglass.accept"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.glass = LightGlass.load(from: defaults, now: Date())
        super.init()
    }

    // MARK: - Lifecycle

    /// Appends the "Light Glass" section to the menu and takes over clicks on the status item while a
    /// block runs (left click: the hourglass; right or control click: the menu).
    func attach(to menu: NSMenu, statusItem: NSStatusItem?) {
        self.menu = menu
        self.statusItem = statusItem
        menu.delegate = self
        let header = NSMenuItem.sectionHeader(title: "Light Glass")
        menu.addItem(header)
        self.header = header
        rebuildSection()
        notificationCenter?.delegate = self
    }

    /// Nil outside an app bundle (the menu smoke harness), where UNUserNotificationCenter would trap.
    private var notificationCenter: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    /// Call once the sun's times are known: finishes a block that ran out while the app was closed and
    /// carries on with one that is still running.
    func restore() {
        heartbeat()
        refreshClickMode()
        updateTicker()
    }

    func stop() {
        glass.save(to: defaults)
        ticker?.invalidate()
        ticker = nil
        holdActivity(false)
    }

    // MARK: - Clock

    /// Advances the timer; ParagondayController calls it on its 15-second update and the ticker every second.
    func heartbeat() {
        let now = Date()
        let before = glass
        let events = glass.tick(now: now, daylight: daylight)
        if glass != before {
            glass.save(to: defaults)
            rebuildSection()
            refreshClickMode()
            updateTicker()
        }
        handle(events)
        if let pop = popover, pop.isShown {
            let snap = glass.snapshot(now: now, daylight: daylight)
            model?.snapshot = snap
            matchAppearance(pop, to: snap)   // the sun can set while the panel is open
        }
    }

    /// The status item while Light Glass has something to say: the block's time left beside an
    /// hourglass, or just the hourglass when a break is waiting. Nil title: show Horizon Time as usual.
    func statusLook(now: Date) -> (title: String?, symbol: String?) {
        if let b = glass.block {
            return (glass.statusText(now: now), b.isPaused ? "hourglass" : "hourglass.bottomhalf.filled")
        }
        if glass.offer?.kind == .rest { return (nil, "hourglass.tophalf.filled") }   // a break is waiting
        return (nil, nil)
    }

    private func updateTicker() {
        let running = glass.block.map { !$0.isPaused } ?? false
        let needed = running || popover?.isShown == true
        if needed, ticker == nil {
            let t = Timer(timeInterval: 1.0, target: self, selector: #selector(tickerFired),
                          userInfo: nil, repeats: true)
            t.tolerance = 0.1
            RunLoop.main.add(t, forMode: .common)
            ticker = t
        } else if !needed {
            ticker?.invalidate()
            ticker = nil
        }
        holdActivity(running)
    }

    private func holdActivity(_ hold: Bool) {
        if hold, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                             reason: "A Light Glass block is running")
        } else if !hold, let a = activity {
            ProcessInfo.processInfo.endActivity(a)
            activity = nil
        }
    }

    @objc private func tickerFired() {
        heartbeat()
        onStatusChange()
    }

    private func changed() {
        glass.save(to: defaults)
        rebuildSection()
        refreshClickMode()
        updateTicker()
        model?.snapshot = glass.snapshot(now: Date(), daylight: daylight)
        onStatusChange()
    }

    // MARK: - Actions

    private func start(_ preset: LightGlass.Preset, minutes: Double? = nil) {
        guard glass.start(preset, minutes: minutes, now: Date(), daylight: daylight) else {
            NSSound.beep()
            return
        }
        askForNotificationsOnce()
        changed()
    }

    private func acceptOffer() {
        guard glass.acceptOffer(now: Date(), daylight: daylight) else { return }
        askForNotificationsOnce()
        changed()
    }

    private func pauseOrResume() {
        guard let b = glass.block else { return }
        if b.isPaused { glass.resume(now: Date()) } else { glass.pause(now: Date()) }
        changed()
    }

    private func stopBlock() {
        glass.stop(now: Date())
        changed()
    }

    private func promptLabel() {
        let alert = NSAlert()
        alert.messageText = "What's next?"
        alert.informativeText = "A few words for this block. They show in the menu and under the hourglass."
        let field = NSTextField(string: glass.label)
        field.placeholderString = "e.g. Draft the dailybell note"
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        glass.setLabel(field.stringValue)
        changed()
    }

    private func promptCustom() {
        let alert = NSAlert()
        alert.messageText = "Custom length"
        alert.informativeText = "How many minutes of light should this block hold? (1 to 720)"
        let field = NSTextField(string: "40")
        field.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let minutes = Double(text), minutes >= 1, minutes <= 720 else {
            NSSound.beep()
            return
        }
        start(.custom, minutes: minutes)
    }

    @objc private func menuStartPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = LightGlass.Preset(rawValue: raw) else { return }
        start(preset)
    }
    @objc private func menuCustom() { promptCustom() }
    @objc private func menuAcceptOffer() { acceptOffer() }
    @objc private func menuPauseResume() { pauseOrResume() }
    @objc private func menuStop() { stopBlock() }
    @objc private func menuLabel() { promptLabel() }
    @objc private func menuShowHourglass() {
        // Let the menu finish closing before the popover anchors to the button.
        DispatchQueue.main.async { [weak self] in self?.showPopover() }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildSection()
    }

    private func rebuildSection() {
        guard let menu = menu, let header = header else { return }
        for item in sectionItems where item.menu === menu { menu.removeItem(item) }
        sectionItems = makeItems(now: Date())
        var index = menu.index(of: header) + 1
        for item in sectionItems {
            menu.insertItem(item, at: index)
            index += 1
        }
    }

    private func makeItems(now: Date) -> [NSMenuItem] {
        let snap = glass.snapshot(now: now, daylight: daylight)
        var items: [NSMenuItem] = []

        if let b = glass.block {
            var line = "\(snap.title) · \(snap.remainingText) left"
            if !snap.label.isEmpty { line += " · \(snap.label)" }
            items.append(info(line))
            if let ends = snap.endsAtText { items.append(info(ends)) }
            if let warning = snap.warning { items.append(info(warning)) }
            items.append(action(b.isPaused ? "Resume" : "Pause", #selector(menuPauseResume)))
            items.append(action(b.kind == .rest ? "End break" : "Stop", #selector(menuStop)))
        } else {
            if let note = snap.note { items.append(info(note)) }
            if let offer = glass.offer {
                items.append(action(offer.title, #selector(menuAcceptOffer)))
                if offer.kind == .rest { items.append(action("Skip break", #selector(menuStop))) }
            }
            for preset in [LightGlass.Preset.pomodoro, .focus50, .deep90, .untilSunset] {
                let item = action(glass.menuTitle(for: preset, now: now, daylight: daylight),
                                  #selector(menuStartPreset(_:)))
                item.representedObject = preset.rawValue
                items.append(item)
            }
            items.append(action("Custom length…", #selector(menuCustom)))
        }

        items.append(action(glass.label.isEmpty ? "What's next?…" : "What's next: \(glass.label)…",
                            #selector(menuLabel)))
        items.append(action("Show hourglass", #selector(menuShowHourglass)))
        items.append(info(snap.todayLine))
        return items
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Status item clicks

    private func refreshClickMode() {
        guard let item = statusItem, let button = item.button else { return }
        if glass.block != nil {
            if item.menu != nil { item.menu = nil }
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        } else if item.menu == nil {
            item.menu = menu
        }
    }

    @objc private func statusClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
            || event?.modifierFlags.contains(.option) == true
        if wantsMenu { showMenu() } else { togglePopover() }
    }

    private func showMenu() {
        guard let item = statusItem, let menu = menu else { return }
        popover?.performClose(nil)
        item.menu = menu
        item.button?.performClick(nil)   // runs the menu until it closes
        item.menu = nil
        refreshClickMode()               // an item may have ended the block; put the menu back if so
    }

    // MARK: - Popover

    private func togglePopover() {
        if let p = popover, p.isShown { p.performClose(nil); return }
        if let closed = popoverClosedAt, Date().timeIntervalSince(closed) < 0.35 { return }
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        let snap = glass.snapshot(now: Date(), daylight: daylight)
        let pop: NSPopover
        if let existing = popover {
            pop = existing
            model?.snapshot = snap
        } else {
            let model = LightGlassModel(snap)
            self.model = model
            pop = NSPopover()
            pop.behavior = .transient
            pop.animates = true
            pop.delegate = self
            let host = NSHostingController(rootView: LightGlassPanel(model: model, actions: panelActions()))
            host.sizingOptions = [.preferredContentSize]
            pop.contentViewController = host
            popover = pop
        }
        matchAppearance(pop, to: snap)
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        updateTicker()
    }

    /// The panel paints its own sky; match the popover's frame and arrow to it.
    private func matchAppearance(_ pop: NSPopover, to snap: LightGlass.Snapshot) {
        let name: NSAppearance.Name = snap.phase == .night ? .darkAqua : .aqua
        if pop.appearance?.name != name { pop.appearance = NSAppearance(named: name) }
    }

    func popoverWillClose(_ notification: Notification) {
        popoverClosedAt = Date()
    }

    func popoverDidClose(_ notification: Notification) {
        updateTicker()
    }

    private func panelActions() -> LightGlassActions {
        LightGlassActions(
            start: { [weak self] preset in self?.start(preset) },
            custom: { [weak self] in self?.promptCustom() },
            pauseResume: { [weak self] in self?.pauseOrResume() },
            stop: { [weak self] in self?.stopBlock() },
            acceptOffer: { [weak self] in self?.acceptOffer() },
            editLabel: { [weak self] in self?.promptLabel() })
    }

    // MARK: - Bell and notification

    private func handle(_ events: [LightGlass.Event]) {
        for event in events {
            guard case .finished(let block, let light, let late, let offer) = event else { continue }
            if late < 60 {
                bell?.stop()
                bell?.play()
            }
            notify(block: block, light: light, late: late, offer: offer)
        }
    }

    private func notify(block: LightGlass.Block, light: TimeInterval, late: TimeInterval, offer: LightGlass.Offer?) {
        // Worded as the web sketch words them: "Block done · 25 m of light", "Break over. What's next?"
        let content = UNMutableNotificationContent()
        var body: [String] = []
        if block.kind == .focus {
            content.title = "Block done · \(Self.spentText(duration: block.duration, light: light))"
            let who = block.label.isEmpty ? "" : "\(block.label): "
            if let offer = offer, offer.kind == .rest {
                let which = offer.longRest ? "long break" : "break"
                body.append("\(who)\(LightGlass.span(block.duration)) done. The \(which) starts when you click.")
            } else if !block.label.isEmpty {
                body.append(block.label)
            }
        } else {
            content.title = "Break over. What's next?"
            if let offer = offer { body.append("Click to start \(Int(offer.minutes.rounded())) min.") }
        }
        // Late means the app was closed or the Mac was asleep when it ended; say when, not why.
        if late >= 60 { body.append("It finished \(LightGlass.words(late)) ago.") }
        content.body = body.joined(separator: " ")
        guard let center = notificationCenter else { return }
        if let offer = offer {
            let accept = UNNotificationAction(identifier: Self.acceptAction, title: offer.title, options: [])
            center.setNotificationCategories([
                UNNotificationCategory(identifier: Self.offerCategory, actions: [accept],
                                       intentIdentifiers: [], options: []),
            ])
            content.categoryIdentifier = Self.offerCategory
        }
        content.sound = nil   // the bell rings instead
        center.add(UNNotificationRequest(identifier: "lightglass.finished", content: content, trigger: nil))
    }

    /// "25 m of light", or "25 m of night" when under a minute of it was daylight (the web's rule).
    static func spentText(duration: TimeInterval, light: TimeInterval) -> String {
        light >= 60 ? "\(LightGlass.span(light)) of light" : "\(LightGlass.span(duration - light)) of night"
    }

    private func askForNotificationsOnce() {
        guard !askedForNotifications else { return }
        askedForNotifications = true
        notificationCenter?.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error {
                FileHandle.standardError.write(Data("[Paragonday] notifications: \(error.localizedDescription)\n".utf8))
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.actionIdentifier
        if id == Self.acceptAction || id == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async { [weak self] in self?.acceptOffer() }
        }
        completionHandler()
    }
}
