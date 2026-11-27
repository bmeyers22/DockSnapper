import AppKit
import ApplicationServices

enum AX {
    // This optional macOS symbol bridges Accessibility and ScreenCaptureKit window IDs.
    // If a macOS release omits it, the preview matcher falls back to titles and bounds.
    private typealias GetWindowID = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindowID: GetWindowID? = {
        guard let process = dlopen(nil, RTLD_LAZY),
              let address = dlsym(process, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(address, to: GetWindowID.self)
    }()

    static func windowID(_ item: AXUIElement) -> CGWindowID? {
        var id = kCGNullWindowID
        guard let getWindowID, getWindowID(item, &id) == .success, id != kCGNullWindowID else { return nil }
        return id
    }

    static let system = AXUIElementCreateSystemWide()

    static func value(_ item: AXUIElement, _ key: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, key as CFString, &result) == .success else { return nil }
        return result
    }

    static func element(_ item: AXUIElement, _ key: String) -> AXUIElement? {
        guard let object = value(item, key), CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
        return (object as! AXUIElement)
    }

    static func frame(_ item: AXUIElement) -> CGRect? {
        guard let p = value(item, kAXPositionAttribute), let s = value(item, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    static func settable(_ item: AXUIElement, _ key: String) -> Bool {
        var yes = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(item, key as CFString, &yes) == .success && yes.boolValue
    }

    static func setFrame(_ item: AXUIElement, _ frame: CGRect) -> Bool {
        var size = frame.size, position = frame.origin
        guard let s = AXValueCreate(.cgSize, &size), let p = AXValueCreate(.cgPoint, &position) else { return false }
        // Shrink before moving. Some applications constrain position based on their current size.
        _ = AXUIElementSetAttributeValue(item, kAXSizeAttribute as CFString, s)
        let moved = AXUIElementSetAttributeValue(item, kAXPositionAttribute as CFString, p)
        let resized = AXUIElementSetAttributeValue(item, kAXSizeAttribute as CFString, s)
        return moved == .success && resized == .success
    }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

final class WindowManager {
    private var history = SnapHistory<AXUIElement>()

    func snap(_ action: Snap) {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return }
        let owner = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = AX.element(owner, kAXFocusedWindowAttribute),
              AX.value(window, "AXFullScreen") as? Bool != true,
              AX.settable(window, kAXSizeAttribute), AX.settable(window, kAXPositionAttribute),
              let current = AX.frame(window), let primary = NSScreen.screens.first else { return }
        let screens = NSScreen.screens
        let frames = screens.map { Geometry.flip($0.frame, primaryHeight: primary.frame.height) }
        let original = history.original(for: window)
        let reference = action == .restore ? original?.window ?? current : current
        guard let index = Geometry.display(for: reference, among: frames) else { return }
        let workArea = Geometry.flip(screens[index].visibleFrame, primaryHeight: primary.frame.height)
        guard let target = history.destination(action, window: window, current: current, workArea: workArea) else { return }
        if AX.setFrame(window, target) && action == .restore { history.didRestore(window) }
    }

    func prune() {
        history.keepWindows { AX.value($0, kAXRoleAttribute) != nil }
    }
}
