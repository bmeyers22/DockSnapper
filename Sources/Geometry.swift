import CoreGraphics
import Foundation

enum Snap: Int, CaseIterable {
    case left = 1, right, fill, restore

    var title: String {
        switch self {
        case .left: return "Left half"
        case .right: return "Right half"
        case .fill: return "Fill desktop"
        case .restore: return "Restore"
        }
    }
}

enum Geometry {
    // AppKit's y axis points up. Accessibility coordinates start at the primary display's top left.
    static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func display(for window: CGRect, among frames: [CGRect]) -> Int? {
        func area(_ frame: CGRect) -> CGFloat {
            let overlap = frame.intersection(window)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        func distance(_ frame: CGRect) -> CGFloat {
            let dx = max(frame.minX - window.midX, window.midX - frame.maxX, 0)
            let dy = max(frame.minY - window.midY, window.midY - frame.maxY, 0)
            return dx * dx + dy * dy
        }
        return frames.indices.min {
            let lhs = frames[$0], rhs = frames[$1]
            return area(lhs) == area(rhs) ? distance(lhs) < distance(rhs) : area(lhs) > area(rhs)
        }
    }

    static func target(_ action: Snap, in frame: CGRect, original: CGRect?) -> CGRect? {
        let half = floor(frame.width / 2)
        switch action {
        case .left: return CGRect(x: frame.minX, y: frame.minY, width: half, height: frame.height)
        case .right: return CGRect(x: frame.minX + half, y: frame.minY, width: frame.width - half, height: frame.height)
        case .fill: return frame
        case .restore:
            guard let original else { return nil }
            let w = min(original.width, frame.width), h = min(original.height, frame.height)
            return CGRect(x: min(max(original.minX, frame.minX), frame.maxX - w),
                          y: min(max(original.minY, frame.minY), frame.maxY - h), width: w, height: h)
        }
    }
}
