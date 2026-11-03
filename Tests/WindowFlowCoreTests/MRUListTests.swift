import Testing
@testable import WindowFlowCore

@Test func mruOrder() {
    var m = MRUList()
    m.touch(1); m.touch(2); m.touch(3)
    #expect(m.order([5, 1, 2, 3, 4]) == [3, 2, 1, 5, 4])
    m.touch(1)
    #expect(m.order([1, 2, 3]) == [1, 3, 2])
    m.remove(1)
    #expect(m.order([1, 2, 3]) == [3, 2, 1])
}
