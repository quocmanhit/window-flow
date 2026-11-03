import Testing
@testable import WindowFlowCore

@Test func remoteTokenLayout() {
    let bytes = RemoteToken.bytes(pid: 0x0102_0304, elementID: 0x1122_3344_5566_7788)
    #expect(bytes.count == 20)
    #expect(Array(bytes[0..<4]) == [0x04, 0x03, 0x02, 0x01])
    #expect(Array(bytes[4..<8]) == [0, 0, 0, 0])
    #expect(Array(bytes[8..<12]) == [0x6f, 0x63, 0x6f, 0x63])
    #expect(Array(bytes[12..<20]) == [0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11])
}

@Test func orderingUsesMRUThenDepthThenInput() {
    var mru = MRUList()
    mru.touch(7)
    mru.touch(3)
    // 3 and 7 are known; 9 is frontmost on screen, 5 behind it, 4 and 8 are not on screen.
    let result = SwitcherOrdering.order([4, 5, 7, 8, 9, 3], mru: mru, zOrder: [9, 1, 5, 2])
    #expect(result == [3, 7, 9, 5, 4, 8])
}

@Test func orderingWithoutZOrderKeepsInput() {
    #expect(SwitcherOrdering.order([2, 1, 3], mru: MRUList(), zOrder: []) == [2, 1, 3])
}

@Test func gridFit() {
    #expect(SwitcherGrid.fit(extent: 1000, item: 128, spacing: 8, padding: 16) == 7)
    #expect(SwitcherGrid.fit(extent: 10, item: 128, spacing: 8, padding: 16) == 1)
}
