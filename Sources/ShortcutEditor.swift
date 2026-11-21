import AppKit
import Carbon

@MainActor
final class ShortcutEditor: NSObject, NSWindowDelegate {
    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 290),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private let hint = NSTextField(wrappingLabelWithString: "")
    private var buttons: [NSButton] = []
    private var shortcuts: [Shortcut] = []
    private var recording: Int?
    private var monitor: Any?
    var suspend: (() -> Void)?
    var resume: (() -> Void)?
    var save: (([Shortcut]) -> String?)?

    override init() {
        super.init()
        panel.title = "DockSnapper Shortcuts"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        let view = panel.contentView!
        for (index, action) in Snap.allCases.enumerated() {
            let y = CGFloat(241 - index * 43)
            let caption = NSTextField(labelWithString: action.title)
            caption.frame = NSRect(x: 24, y: y + 4, width: 170, height: 20)
            view.addSubview(caption)
            let button = NSButton(title: "", target: self, action: #selector(record(_:)))
            button.tag = index
            button.setAccessibilityLabel("Change shortcut for " + action.title)
            button.frame = NSRect(x: 204, y: y, width: 194, height: 32)
            view.addSubview(button)
            buttons.append(button)
        }
        hint.frame = NSRect(x: 24, y: 51, width: 370, height: 45)
        hint.textColor = .secondaryLabelColor
        view.addSubview(hint)
        let reset = NSButton(title: "Restore Defaults", target: self, action: #selector(resetDefaults))
        reset.frame = NSRect(x: 20, y: 12, width: 145, height: 32)
        view.addSubview(reset)
        panel.center()
    }

    func show(_ choices: [Shortcut]) {
        shortcuts = choices
        refresh()
        hint.stringValue = "Click a shortcut to record a new combination."
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func refresh() {
        for (index, button) in buttons.enumerated() { button.title = shortcuts[index].label }
    }

    @objc private func record(_ sender: NSButton) {
        endRecording()
        recording = sender.tag
        suspend?()
        sender.title = "Press shortcut…"
        hint.stringValue = "Hold a modifier and press a key. Escape cancels."
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            self.receive(event)
            return nil
        }
    }

    private func receive(_ event: NSEvent) {
        guard let index = recording else { return }
        if event.keyCode == kVK_Escape && event.modifierFlags.intersection([.command,.option,.control,.shift]).isEmpty {
            endRecording()
            return
        }
        let pairs: [(NSEvent.ModifierFlags, Int)] = [(.command,cmdKey),(.option,optionKey),(.control,controlKey),(.shift,shiftKey)]
        let flags = pairs.reduce(UInt32(0)) { value, pair in
            event.modifierFlags.contains(pair.0) ? value | UInt32(pair.1) : value
        }
        guard flags != 0 else { hint.stringValue = "Include Command, Control, Option, or Shift."; return }
        let key = Int(event.keyCode)
        let names: [Int: String] = [kVK_LeftArrow:"←", kVK_RightArrow:"→", kVK_UpArrow:"↑", kVK_DownArrow:"↓", kVK_Space:"Space",
                     kVK_Return:"Return", kVK_Tab:"Tab", kVK_Delete:"Delete", kVK_Escape:"Esc", kVK_ForwardDelete:"Forward Delete",
                     kVK_Home:"Home", kVK_End:"End", kVK_PageUp:"Page Up", kVK_PageDown:"Page Down"]
        let functionKeys: [Int] = [kVK_F1,kVK_F2,kVK_F3,kVK_F4,kVK_F5,kVK_F6,kVK_F7,kVK_F8,kVK_F9,kVK_F10,kVK_F11,kVK_F12,
                            kVK_F13,kVK_F14,kVK_F15,kVK_F16,kVK_F17,kVK_F18,kVK_F19,kVK_F20]
        let printable = event.characters(byApplyingModifiers: [])?.uppercased()
        let name: String
        if let special = names[key] {
            name = special
        } else if let index = functionKeys.firstIndex(of: key) {
            name = "F" + String(index + 1)
        } else if let printable, !printable.isEmpty {
            name = printable
        } else {
            name = "Key \(key)"
        }
        let new = Shortcut(key: UInt32(key), modifiers: flags, name: name)
        if let duplicate = shortcuts.indices.first(where: { $0 != index && shortcuts[$0].conflicts(with: new) }) {
            hint.stringValue = "Already assigned to \(Snap.allCases[duplicate].title). Try another combination."
            return
        }
        var proposed = shortcuts
        proposed[index] = new
        commit(proposed)
    }

    private func commit(_ proposed: [Shortcut]) {
        endRecording()
        if let error = save?(proposed) {
            hint.stringValue = error
        } else {
            shortcuts = proposed
            refresh()
            hint.stringValue = "Shortcuts saved."
        }
    }

    @objc private func resetDefaults() { commit(Shortcut.initial()) }

    private func endRecording() {
        guard recording != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        refresh()
        hint.stringValue = "Click a shortcut to record a new combination."
        resume?()
    }

    func windowDidResignKey(_ notification: Notification) { endRecording() }
    func windowWillClose(_ notification: Notification) { endRecording() }
}
