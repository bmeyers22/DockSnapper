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

var history = SnapHistory<Int>()
let spanning = CGRect(x: -60, y: 90, width: 650, height: 480)
let second = CGRect(x: 260, y: 210, width: 700, height: 500)
let firstLeft = history.destination(.left, window: 1, current: spanning, workArea: primary)!
_ = history.destination(.right, window: 2, current: second, workArea: primary)
_ = history.destination(.fill, window: 1, current: firstLeft, workArea: primary)
expect(history.destination(.restore, window: 1, current: primary, workArea: primary) == spanning, "restore the exact starting frame across a sequence, including straddling displays")
history.didRestore(1)
expect(history.original(for: 1) == nil && history.original(for: 2)?.window == second, "restore histories are independent")
expect(history.destination(.restore, window: 2, current: primary, workArea: work) == Geometry.target(.restore, in: work, original: second), "restore into the new work area after a display change")
history.keepWindows { _ in false }
expect(history.original(for: 2) == nil, "discard closed windows")
