import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let windows = WindowManager()
    private let hover = DockHover()
    private lazy var keys = HotKeys { [weak self] in self?.windows.snap($0) }
    private let defaults = UserDefaults.standard
    private var status: NSStatusItem!
    private var problem: String?
    private var trusted = false
    private var timer: Timer?
    private var pruneTicks = 0
    private var chord: Chord { Chord(rawValue: defaults.integer(forKey: "modifiers")) ?? .shiftOption }
    private var paused: Bool { defaults.bool(forKey: "paused") }
    private var previews: Bool { !defaults.bool(forKey: "hidePreviews") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "DockSnapper")
        status.button?.toolTip = "DockSnapper"
        let menu = NSMenu()
        menu.delegate = self
        status.menu = menu
        configure()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        if !defaults.bool(forKey: "introduced") {
            defaults.set(true, forKey: "introduced")
            DispatchQueue.main.async { self.introduce() }
        }
    }

    private func introduce() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Set up DockSnapper"
        alert.informativeText = "Allow Accessibility to snap and select windows. For window images, allow Screen & System Audio Recording from the DockSnapper menu. Its split-window icon is in your menu bar."
        alert.addButton(withTitle: "Enable Accessibility")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { accessibility() }
    }

    private func refresh() {
        if trusted != AXIsProcessTrusted() { configure() }
        pruneTicks += 1
        if pruneTicks >= 30 { windows.prune(); pruneTicks = 0 }
    }

    private func configure() {
        trusted = AXIsProcessTrusted()
        keys.clear()
        problem = trusted && !paused ? keys.register(chord) : nil
        if trusted && previews { hover.start() } else { hover.stop() }
    }

    private func entry(_ menu: NSMenu, _ title: String, _ selector: Selector? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        _ = entry(menu, "DockSnapper")
        if !trusted { _ = entry(menu, "Enable Accessibility…", #selector(accessibility)) }
        if !CGPreflightScreenCaptureAccess() { _ = entry(menu, "Enable Window Images…", #selector(recording)) }
        if let problem { _ = entry(menu, problem) }
        menu.addItem(.separator())
        _ = entry(menu, "\(chord.label) ← / →   Left / Right half")
        _ = entry(menu, "\(chord.label) ↑ / ↓   Fill / Restore")
        let modifiers = entry(menu, "Shortcut modifiers")
        let choices = NSMenu()
        for option in Chord.allCases {
            let item = entry(choices, "\(option.label) + Arrow keys", #selector(change(_:)))
            item.tag = option.rawValue
            item.state = option == chord ? .on : .off
        }
        modifiers.submenu = choices
        _ = entry(menu, paused ? "Resume snapping" : "Pause snapping", #selector(toggleSnap))
        entry(menu, "Dock thumbnails", #selector(togglePreview)).state = previews ? .on : .off
        menu.addItem(.separator())
        _ = entry(menu, "Quit DockSnapper", #selector(quit))
    }

    @objc private func change(_ sender: NSMenuItem) { defaults.set(sender.tag, forKey: "modifiers"); configure() }
    @objc private func toggleSnap() { defaults.set(!paused, forKey: "paused"); configure() }
    @objc private func togglePreview() { defaults.set(previews, forKey: "hidePreviews"); configure() }
    @objc private func accessibility() {
        AX.requestTrust()
        openPrivacy("Privacy_Accessibility")
    }
    @objc private func recording() {
        if !CGRequestScreenCaptureAccess() { openPrivacy("Privacy_ScreenCapture") }
    }
    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
    withExtendedLifetime(delegate) {}
}
