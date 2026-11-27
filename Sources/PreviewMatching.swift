import Foundation
import CoreGraphics

struct PreviewWindow {
    let title: String
    let bounds: CGRect?
    var id: CGWindowID? = nil
    var layer: Int = 0
}

enum PreviewMatching {
    // Chrome's Accessibility title may include the browser and profile after the page title.
    // Compare whole page titles, including any punctuation that is part of the page itself.
    static func matches(_ item: PreviewWindow, candidates: [PreviewWindow], chromeName: String?) -> Int? {
        if let id = item.id { return candidates.firstIndex { $0.id == id } }
        let normal = candidates.indices.filter { candidates[$0].layer == 0 }
        let exact = normal.filter { !item.title.isEmpty && candidates[$0].title == item.title }
        if exact.count == 1 { return exact.first }
        var pool = exact
        if pool.isEmpty, let chromeName {
            let page = pageTitle(item.title, browser: chromeName)
            pool = normal.filter {
                !page.isEmpty && pageTitle(candidates[$0].title, browser: chromeName) == page
            }
            if pool.count == 1 { return pool.first }
        }
        guard let rect = item.bounds else { return nil }
        let aligned = (pool.isEmpty ? normal : pool).filter { index in
            guard let other = candidates[index].bounds else { return false }
            return abs(other.minX - rect.minX) <= 2 && abs(other.minY - rect.minY) <= 2 &&
                abs(other.width - rect.width) <= 2 && abs(other.height - rect.height) <= 2
        }
        return aligned.count == 1 ? aligned.first : nil
    }

    private static func pageTitle(_ title: String, browser: String) -> String {
        let words = title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        for dash in [" - ", " — ", " – "] {
            guard let suffix = words.range(of: dash + browser, options: .backwards) else { continue }
            let tail = words[suffix.upperBound...]
            if tail.isEmpty || [" - ", " — ", " – ", " (", ", "].contains(where: { tail.hasPrefix($0) }) {
                return String(words[..<suffix.lowerBound])
            }
        }
        return words
    }
}
