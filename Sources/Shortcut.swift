import Foundation
import Carbon

struct Shortcut: Codable, Equatable {
    let key: UInt32
    let modifiers: UInt32
    let name: String

    var label: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .compactMap { modifiers & UInt32($0.0) == 0 ? nil : $0.1 }.joined() + name
    }

    static func initial(legacyModifierIndex: Int? = nil) -> [Shortcut] {
        let legacy = [shiftKey | optionKey, controlKey | optionKey, controlKey | shiftKey, cmdKey | optionKey]
        let flags = legacyModifierIndex.flatMap { legacy.indices.contains($0) ? legacy[$0] : nil } ?? (cmdKey | shiftKey)
        return zip([kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow], ["←","→","↑","↓"]).map {
            Shortcut(key: UInt32($0.0), modifiers: UInt32(flags), name: $0.1)
        }
    }

    static func load(from defaults: UserDefaults) -> [Shortcut] {
        if let data = defaults.data(forKey: "shortcuts"),
           let saved = try? JSONDecoder().decode([Shortcut].self, from: data),
           saved.count == Snap.allCases.count { return saved }
        return initial(legacyModifierIndex: defaults.object(forKey: "modifiers") as? Int)
    }

    func conflicts(with other: Shortcut) -> Bool { key == other.key && modifiers == other.modifiers }
}
