import CoreGraphics
import Testing
@testable import WindowFlowCore

private let screen = CGRect(x: 0, y: 25, width: 1200, height: 775)
private let left = CGRect(x: 0, y: 25, width: 600, height: 775)
private let right = CGRect(x: 600, y: 25, width: 600, height: 775)

private func c(_ id: UInt32, _ frame: CGRect, space: Int = 1, order: Int) -> GroupCandidate {
    GroupCandidate(id: id, frame: frame, space: space, order: order)
}

private func groups(_ windows: [GroupCandidate], screens: [CGRect] = [screen], tolerance: CGFloat = 8) -> [[UInt32]] {
    WindowGrouping.groups(windows, screens: screens, tolerance: tolerance)
}

@Test func halvesFormAGroup() {
    #expect(groups([c(1, left, order: 0), c(2, right, order: 1)]) == [[1, 2]])
}

@Test func halvesWithGapFormAGroup() {
    let a = CGRect(x: 10, y: 35, width: 585, height: 755), b = CGRect(x: 605, y: 35, width: 585, height: 755)
    #expect(groups([c(1, a, order: 0), c(2, b, order: 1)], tolerance: 18) == [[1, 2]])
}

@Test func largeGapStillCountsAsCovered() {
    let a = CGRect(x: 30, y: 55, width: 555, height: 715), b = CGRect(x: 615, y: 55, width: 555, height: 715)
    #expect(groups([c(1, a, order: 0), c(2, b, order: 1)], tolerance: 38) == [[1, 2]])
}

@Test func differentSpacesDoNotGroup() {
    #expect(groups([c(1, left, space: 1, order: 0), c(2, right, space: 2, order: 1)]).isEmpty)
}

@Test func halfPlusSmallFloatingWindowIsNotAGroup() {
    let small = CGRect(x: 800, y: 300, width: 200, height: 150)
    #expect(groups([c(1, left, order: 0), c(2, small, order: 1)]).isEmpty)
}

@Test func threeThirdsAndFourQuartersGroup() {
    let thirds = [0, 1, 2].map { CGRect(x: CGFloat($0) * 400, y: 25, width: 400, height: 775) }
    #expect(groups(thirds.enumerated().map { c(UInt32($0.offset + 1), $0.element, order: $0.offset) }) == [[1, 2, 3]])
    let quarters = [
        CGRect(x: 600, y: 412.5, width: 600, height: 387.5), CGRect(x: 0, y: 25, width: 600, height: 387.5),
        CGRect(x: 0, y: 412.5, width: 600, height: 387.5), CGRect(x: 600, y: 25, width: 600, height: 387.5),
    ]
    // Reading order: top-left, top-right, bottom-left, bottom-right.
    #expect(groups(quarters.enumerated().map { c(UInt32($0.offset + 1), $0.element, order: $0.offset) }) == [[2, 4, 3, 1]])
}

@Test func overlappingWindowsDoNotGroup() {
    let a = CGRect(x: 0, y: 25, width: 800, height: 775), b = CGRect(x: 400, y: 25, width: 800, height: 775)
    #expect(groups([c(1, a, order: 0), c(2, b, order: 1)]).isEmpty)
}

@Test func twoDisplaysEachWithAPair() {
    let second = CGRect(x: -1000, y: 0, width: 1000, height: 800)
    let windows = [
        c(1, left, order: 0), c(2, right, order: 1),
        c(3, CGRect(x: -1000, y: 0, width: 500, height: 800), order: 2),
        c(4, CGRect(x: -500, y: 0, width: 500, height: 800), order: 3),
    ]
    #expect(groups(windows, screens: [screen, second]) == [[1, 2], [3, 4]])
}

@Test func greedyFollowsSwitcherOrder() {
    let cover = CGRect(x: 300, y: 25, width: 600, height: 775)
    #expect(groups([c(1, left, order: 0), c(2, right, order: 1), c(3, cover, order: 2)]) == [[1, 2]])
    #expect(groups([c(3, cover, order: 0), c(1, left, order: 1), c(2, right, order: 2)]) == [[1, 2]])
}

@Test func maximizedWindowFirstDoesNotHideThePairBehindIt() {
    let windows = [c(9, screen, order: 0), c(1, left, order: 1), c(2, right, order: 2)]
    #expect(groups(windows) == [[1, 2]])
}

@Test func atMostFourMembers() {
    let quarters = [
        CGRect(x: 0, y: 25, width: 600, height: 387.5), CGRect(x: 600, y: 25, width: 600, height: 387.5),
        CGRect(x: 0, y: 412.5, width: 600, height: 387.5), CGRect(x: 600, y: 412.5, width: 600, height: 387.5),
    ]
    let extra = c(9, CGRect(x: 0, y: 25, width: 10, height: 10), order: 4)
    #expect(groups(quarters.enumerated().map { c(UInt32($0.offset + 1), $0.element, order: $0.offset) } + [extra]) == [[1, 2, 3, 4]])
}

@Test func negativeOriginDisplay() {
    let display = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
    let a = CGRect(x: -1920, y: -200, width: 960, height: 1080), b = CGRect(x: -960, y: -200, width: 960, height: 1080)
    #expect(groups([c(1, a, order: 0), c(2, b, order: 1)], screens: [screen, display]) == [[1, 2]])
}

@Test func groupTitles() {
    #expect(GroupTitle.make([("Zalo", "Chat"), ("Google Chat", "Inbox")]) == "Zalo + Google Chat")
    #expect(GroupTitle.make([("Zalo", "A"), ("Zalo", "B")]) == "A + B")
    #expect(GroupTitle.make([("Zalo", ""), ("Zalo", "B")]) == "Zalo + B")
    #expect(GroupTitle.make([("A", "x"), ("B", "y"), ("A", "z")]) == "A + B")
}

@Test func smallWindowBetweenThePairInSwitcherOrderDoesNotBreakIt() {
    let corner = CGRect(x: 1100, y: 25, width: 100, height: 100)
    #expect(groups([c(1, left, order: 0), c(9, corner, order: 1), c(2, right, order: 2)]) == [[1, 2]])
}
