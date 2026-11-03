import CoreGraphics
import Testing
@testable import WindowFlowCore

private let r = CGRect(x: 0, y: 0, width: 600, height: 800)

@Test func cyclesThroughThreeSteps() {
    var t = CycleTracker()
    var steps: [Int] = []
    for _ in 0..<4 {
        steps.append(t.step(for: .leftHalf, window: 1, current: r))
        t.record(.leftHalf, window: 1, result: r)
    }
    #expect(steps == [0, 1, 2, 0])
}

@Test func toleranceAllowsTwoPoints() {
    var t = CycleTracker()
    _ = t.step(for: .leftHalf, window: 1, current: r)
    t.record(.leftHalf, window: 1, result: r)
    #expect(t.step(for: .leftHalf, window: 1, current: r.offsetBy(dx: 2, dy: 0)) == 1)
}

@Test func resetsOnChange() {
    func primed() -> CycleTracker {
        var t = CycleTracker()
        _ = t.step(for: .leftHalf, window: 1, current: r)
        t.record(.leftHalf, window: 1, result: r)
        return t
    }
    var a = primed(); #expect(a.step(for: .rightHalf, window: 1, current: r) == 0)
    var b = primed(); #expect(b.step(for: .leftHalf, window: 2, current: r) == 0)
    var c = primed(); #expect(c.step(for: .leftHalf, window: 1, current: r.offsetBy(dx: 50, dy: 0)) == 0)
}

@Test func nonCyclingActionsAlwaysZero() {
    var t = CycleTracker()
    for _ in 0..<3 {
        #expect(t.step(for: .maximize, window: 1, current: r) == 0)
        t.record(.maximize, window: 1, result: r)
    }
}
