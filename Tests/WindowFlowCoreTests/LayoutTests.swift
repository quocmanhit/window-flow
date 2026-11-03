import CoreGraphics
import Testing
@testable import WindowFlowCore

private let screen = CGRect(x: 0, y: 25, width: 1200, height: 775)

private func close(_ a: CGRect?, _ b: CGRect, sourceLocation: SourceLocation = #_sourceLocation) {
    guard let a else { Issue.record("nil frame", sourceLocation: sourceLocation); return }
    let ok = abs(a.minX - b.minX) < 1e-9 && abs(a.minY - b.minY) < 1e-9
        && abs(a.width - b.width) < 1e-9 && abs(a.height - b.height) < 1e-9
    #expect(ok, "\(a) != \(b)", sourceLocation: sourceLocation)
}

private func frame(_ action: WindowAction, window: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300),
                   screen: CGRect = screen, gap: CGFloat = 0, step: Int = 0) -> CGRect? {
    Layout.frame(for: action, window: window, screen: screen, gap: gap, step: step)
}

@Test func halvesCycle() {
    close(frame(.leftHalf), CGRect(x: 0, y: 25, width: 600, height: 775))
    close(frame(.leftHalf, step: 1), CGRect(x: 0, y: 25, width: 800, height: 775))
    close(frame(.leftHalf, step: 2), CGRect(x: 0, y: 25, width: 400, height: 775))
    close(frame(.rightHalf, step: 1), CGRect(x: 400, y: 25, width: 800, height: 775))
}

@Test func cornersAndThirds() {
    close(frame(.topLeft), CGRect(x: 0, y: 25, width: 600, height: 387.5))
    close(frame(.centerThird), CGRect(x: 400, y: 25, width: 400, height: 775))
    close(frame(.lastTwoThirds), CGRect(x: 400, y: 25, width: 800, height: 775))
}

@Test func maximizeVariants() {
    close(frame(.maximize), screen)
    close(frame(.almostMaximize), CGRect(x: 60, y: 63.75, width: 1080, height: 697.5))
    close(frame(.maximizeHeight, window: CGRect(x: 100, y: 300, width: 500, height: 200)),
          CGRect(x: 100, y: 25, width: 500, height: 775))
}

@Test func resizeAndCenter() {
    close(frame(.larger), CGRect(x: 70, y: 70, width: 460, height: 360))
    close(frame(.smaller), CGRect(x: 130, y: 130, width: 340, height: 240))
    let small = frame(.smaller, window: CGRect(x: 0, y: 25, width: 330, height: 210))!
    #expect(small.width >= 320 && small.height >= 200)
    close(frame(.center, window: CGRect(x: 0, y: 0, width: 5000, height: 5000)), screen)
}

@Test func gaps() {
    close(frame(.leftHalf, gap: 10), CGRect(x: 10, y: 35, width: 585, height: 755))
    close(frame(.rightHalf, gap: 10), CGRect(x: 605, y: 35, width: 585, height: 755))
}

@Test func negativeOriginScreen() {
    let s = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
    close(frame(.rightHalf, screen: s), CGRect(x: -960, y: -200, width: 960, height: 1080))
}

@Test func nonLayoutActionsReturnNil() {
    #expect(frame(.restore) == nil)
    #expect(frame(.nextDisplay) == nil)
    #expect(frame(.previousDisplay) == nil)
}

@Test func flippedIsItsOwnInverse() {
    let r = CGRect(x: 3, y: 7, width: 100, height: 50)
    #expect(flipped(flipped(r, primaryHeight: 800), primaryHeight: 800) == r)
    #expect(flipped(CGRect(x: 0, y: 0, width: 100, height: 50), primaryHeight: 800)
        == CGRect(x: 0, y: 750, width: 100, height: 50))
}

@Test func realignKeepsHuggedEdge() {
    let target = CGRect(x: 600, y: 25, width: 600, height: 775)
    #expect(Layout.realign(actual: CGSize(width: 700, height: 775), target: target, screen: screen, action: .rightHalf).x == 500)
    let bottom = CGRect(x: 0, y: 412.5, width: 1200, height: 387.5)
    #expect(Layout.realign(actual: CGSize(width: 1200, height: 500), target: bottom, screen: screen, action: .bottomHalf).y == 300)
    let mid = CGRect(x: 60, y: 63.75, width: 1080, height: 697.5)
    #expect(Layout.realign(actual: CGSize(width: 800, height: 600), target: mid, screen: screen, action: .center).x == 200)
}

@Test func realignClampsAndHandlesOversize() {
    let target = CGRect(x: 600, y: 25, width: 600, height: 775)
    let wide = Layout.realign(actual: CGSize(width: 1500, height: 900), target: target, screen: screen, action: .rightHalf)
    #expect(wide == CGPoint(x: 0, y: 25))
    let left = Layout.realign(actual: CGSize(width: 700, height: 775), target: CGRect(x: 0, y: 25, width: 600, height: 775),
                              screen: screen, action: .leftHalf)
    #expect(left.x == 0)
}
