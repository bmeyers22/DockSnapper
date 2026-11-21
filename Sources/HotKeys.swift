import AppKit
import Carbon

enum Chord: Int, CaseIterable {
    case shiftOption, controlOption, controlShift, commandOption
    var label: String { ["⇧⌥", "⌃⌥", "⌃⇧", "⌘⌥"][rawValue] }
    var flags: UInt32 { UInt32([shiftKey | optionKey, controlKey | optionKey, controlKey | shiftKey, cmdKey | optionKey][rawValue]) }
}

final class HotKeys {
    private var handler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    let perform: (Snap) -> Void
    init(perform: @escaping (Snap) -> Void) { self.perform = perform }

    func clear() {
        registrations.forEach { UnregisterEventHotKey($0) }
        registrations.removeAll()
    }

    func register(_ chord: Chord) -> String? {
        clear()
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, ref, context in
                guard let ref, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(ref, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, id.signature == 0x44534E50, let action = Snap(rawValue: Int(id.id)) else { return OSStatus(eventNotHandledErr) }
                Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue().perform(action)
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
            if status != noErr { return "Keyboard shortcuts are unavailable (\(status))." }
        }
        let codes = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow]
        for (action, code) in zip(Snap.allCases, codes) {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x44534E50, id: UInt32(action.rawValue))
            let result = RegisterEventHotKey(UInt32(code), chord.flags, id, GetApplicationEventTarget(), 0, &ref)
            guard result == noErr, let ref else {
                clear()
                return "\(action.title) could not register. Choose another shortcut modifier."
            }
            registrations.append(ref)
        }
        return nil
    }

    deinit {
        clear()
        if let handler { RemoveEventHandler(handler) }
    }
}
