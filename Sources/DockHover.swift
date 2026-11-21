import AppKit
import ScreenCaptureKit

@MainActor
final class DockHover {
    private let preview = PreviewPanel()
    private var tick: Timer?
    private var capture: Task<Void, Never>?
    private var hovered: pid_t?
    private var showing = false
    private var arrived: TimeInterval = 0
    private var lastInside: TimeInterval = 0

    func start() {
        guard tick == nil else { return }
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    func stop() {
        tick?.invalidate()
        tick = nil
        dismiss()
    }

    private func dismiss() {
        capture?.cancel()
        capture = nil
        if showing { preview.hide() }
        hovered = nil
        showing = false
    }

    private func poll() {
        guard AXIsProcessTrusted() else { if showing { dismiss() }; return }
        let mouse = NSEvent.mouseLocation
        let time = ProcessInfo.processInfo.systemUptime
        if showing && preview.panel.frame.contains(mouse) {
            lastInside = time
            return
        }
        guard let primary = NSScreen.screens.first,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
              nearDockEdge(mouse, screen.frame),
              let (app, frame) = dockItem(at: CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)) else {
            if hovered != nil && time - lastInside > 0.38 { dismiss() }
            return
        }
        lastInside = time
        if hovered != app.processIdentifier {
            dismiss()
            hovered = app.processIdentifier
            arrived = time
        }
        if !showing && time - arrived >= 0.30 {
            arrived = time
            show(app, anchor: Geometry.flip(frame, primaryHeight: primary.frame.height), screen: screen)
        }
    }

    private func nearDockEdge(_ p: CGPoint, _ f: CGRect) -> Bool {
        min(p.x - f.minX, f.maxX - p.x, p.y - f.minY) < 192
    }

    private func dockItem(at point: CGPoint) -> (NSRunningApplication, CGRect)? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AX.system, Float(point.x), Float(point.y), &hit) == .success,
              var el = hit else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        guard NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock" else { return nil }
        for _ in 0..<4 {
            if AX.value(el, kAXSubroleAttribute) as? String == "AXApplicationDockItem",
               let url = AX.value(el, kAXURLAttribute) as? URL,
               let app = runningApp(at: url),
               let frame = AX.frame(el) { return (app, frame) }
            guard let parent = AX.element(el, kAXParentAttribute) else { break }
            el = parent
        }
        return nil
    }

    private func runningApp(at url: URL) -> NSRunningApplication? {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let apps = NSWorkspace.shared.runningApplications
        if let exact = apps.first(where: { $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == resolved }) { return exact }
        guard let id = Bundle(url: url)?.bundleIdentifier else { return nil }
        let matches = apps.filter { $0.bundleIdentifier == id }
        return matches.count == 1 ? matches.first : nil
    }

    private func show(_ app: NSRunningApplication, anchor: CGRect, screen: NSScreen) {
        let owner = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(owner, 0.25)
        let windows = AX.value(owner, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let items: [WindowChoice] = windows.compactMap { window in
            guard AX.value(window, kAXRoleAttribute) as? String == kAXWindowRole else { return nil }
            let title = AX.value(window, kAXTitleAttribute) as? String ?? ""
            return WindowChoice(window: window, title: title.isEmpty ? (app.localizedName ?? "Window") : title,
                                bounds: AX.frame(window), minimized: AX.value(window, kAXMinimizedAttribute) as? Bool == true)
        }
        guard !items.isEmpty else { return }
        showing = true
        preview.show(app: app, items: items, anchor: anchor, screen: screen) { [weak self] item in
            self?.dismiss()
            if item.minimized { AXUIElementSetAttributeValue(item.window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
            app.activate(options: [])
            AXUIElementPerformAction(item.window, kAXRaiseAction as CFString)
        }
        guard CGPreflightScreenCaptureAccess() else { return }
        capture = Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                try Task.checkCancellation()
                let candidates = content.windows.filter { $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0 }
                let matches = items.map { Self.match($0, candidates: candidates) }
                for (index, matched) in matches.enumerated() {
                    guard let window = matched,
                          matches.compactMap({ $0?.windowID }).filter({ $0 == window.windowID }).count == 1 else { continue }
                    try Task.checkCancellation()
                    let config = SCStreamConfiguration()
                    let size = window.frame.size
                    guard size.width > 0, size.height > 0 else { continue }
                    let scale = min(336 / size.width, 198 / size.height)
                    config.width = max(2, Int(size.width * scale))
                    config.height = max(2, Int(size.height * scale))
                    config.showsCursor = false
                    config.ignoreShadowsSingleWindow = true
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { continue }
                    try Task.checkCancellation()
                    self?.preview.setImage(image, at: index)
                }
            } catch { /* Titles stay selectable when macOS cannot supply images. */ }
        }
    }

    private static func match(_ item: WindowChoice, candidates: [SCWindow]) -> SCWindow? {
        let titled = candidates.filter { $0.title == item.title }
        if titled.count == 1 { return titled.first }
        guard let rect = item.bounds else { return nil }
        let pool = titled.isEmpty ? candidates : titled
        let aligned = pool.filter {
            abs($0.frame.minX - rect.minX) <= 2 && abs($0.frame.minY - rect.minY) <= 2 &&
            abs($0.frame.width - rect.width) <= 2 && abs($0.frame.height - rect.height) <= 2
        }
        return aligned.count == 1 ? aligned.first : nil
    }
}
