import CoreGraphics
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fatalError(name) }
    print("PASS \(name)")
}

let work = CGRect(x: -1440, y: -120, width: 1439, height: 870)
let left = Geometry.target(.left, in: work, original: nil)!
let right = Geometry.target(.right, in: work, original: nil)!
expect(left.union(right) == work && left.maxX == right.minX, "odd widths tile without gaps")
expect(Geometry.target(.fill, in: work, original: nil) == work, "fill respects usable frame")
let initial = CGRect(x: -800, y: 40, width: 600, height: 400)
expect(Geometry.target(.restore, in: work, original: initial) == initial, "restore normal bounds")
expect(Geometry.target(.restore, in: work, original: nil) == nil, "restore before snapping does nothing")
let primary = CGRect(x: 0, y: 0, width: 1728, height: 1117)
expect(Geometry.display(for: initial, among: [primary, work]) == 1, "negative-origin display")
expect(Geometry.display(for: initial, among: [primary]) == 0, "disconnected display fallback")
let recovered = Geometry.target(.restore, in: primary, original: initial)!
expect(primary.contains(recovered) && recovered.size == initial.size, "restore after disconnection")
expect(Geometry.flip(Geometry.flip(work, primaryHeight: 1117), primaryHeight: 1117) == work, "coordinate conversion")
