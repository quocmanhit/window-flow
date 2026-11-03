import Testing
@testable import WindowFlowCore

@Test func selectionBounds() {
    var empty = SwitcherSelection(count: 0)
    #expect(empty.index == nil)
    empty.next(); empty.previous()
    #expect(empty.index == nil)
    #expect(SwitcherSelection(count: 1).index == 0)
}

@Test func selectionWraps() {
    var s = SwitcherSelection(count: 3)
    #expect(s.index == 1)
    s.next(); #expect(s.index == 2)
    s.next(); #expect(s.index == 0)
    s.previous(); #expect(s.index == 2)
}

@Test func selectionStart() {
    #expect(SwitcherSelection(count: 3, start: 0).index == 0)
    #expect(SwitcherSelection(count: 1, start: 1).index == 0)
    #expect(SwitcherSelection(count: 0, start: 0).index == nil)
    var s = SwitcherSelection(count: 3, start: 0)
    s.previous(); #expect(s.index == 2)
}
