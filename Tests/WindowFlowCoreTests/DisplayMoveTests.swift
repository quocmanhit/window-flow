import CoreGraphics
import Testing
@testable import WindowFlowCore

@Test func targetWraps() {
    #expect(DisplayMove.target(from: 1, count: 2, forward: true) == 0)
    #expect(DisplayMove.target(from: 0, count: 1, forward: true) == 0)
    #expect(DisplayMove.target(from: 0, count: 3, forward: false) == 2)
}

@Test func orderByPosition() {
    let screens = [CGRect(x: 0, y: 0, width: 1512, height: 944),
                   CGRect(x: -1512, y: 0, width: 1512, height: 944),
                   CGRect(x: 3840, y: 0, width: 1000, height: 800)]
    #expect(DisplayMove.order(screens) == [1, 0, 2])
}

@Test func proportionalMove() {
    let from = CGRect(x: 1920, y: 0, width: 1512, height: 944)
    let to = CGRect(x: 0, y: 25, width: 3840, height: 2135)
    let r = DisplayMove.frame(window: CGRect(x: 1920, y: 0, width: 756, height: 944), from: from, to: to)
    #expect(abs(r.minX) < 1e-9 && abs(r.minY - 25) < 1e-9)
    #expect(abs(r.width - 1920) < 1e-9 && abs(r.height - 2135) < 1e-9)
}

@Test func shrinksAndStaysInside() {
    let from = CGRect(x: 0, y: 0, width: 3000, height: 2000)
    let to = CGRect(x: -1512, y: -300, width: 1512, height: 944)
    for w in [CGRect(x: 0, y: 0, width: 3000, height: 2000), CGRect(x: 2500, y: 1800, width: 500, height: 200)] {
        let r = DisplayMove.frame(window: w, from: from, to: to)
        #expect(to.contains(r), "\(r)")
    }
    let big = DisplayMove.frame(window: CGRect(x: 0, y: 0, width: 3000, height: 2000), from: from, to: to)
    #expect(big.width <= to.width + 1e-9)
}
