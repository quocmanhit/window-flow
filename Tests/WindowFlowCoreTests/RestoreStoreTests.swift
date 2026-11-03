import CoreGraphics
import Testing
@testable import WindowFlowCore

private let original = CGRect(x: 100, y: 100, width: 400, height: 300)
private let applied = CGRect(x: 0, y: 25, width: 600, height: 775)

@Test func keepsFirstFrameWhileUntouched() {
    var s = RestoreStore()
    s.willApply(window: 1, current: original)
    s.lastApplied(window: 1, frame: applied)
    s.willApply(window: 1, current: applied.offsetBy(dx: 1, dy: 1))
    s.lastApplied(window: 1, frame: applied)
    #expect(s.takeRestore(window: 1) == original)
}

@Test func replacesWhenUserMoved() {
    var s = RestoreStore()
    s.willApply(window: 1, current: original)
    s.lastApplied(window: 1, frame: applied)
    let moved = CGRect(x: 300, y: 300, width: 600, height: 775)
    s.willApply(window: 1, current: moved)
    #expect(s.takeRestore(window: 1) == moved)
}

@Test func takeClearsAndForgetDrops() {
    var s = RestoreStore()
    s.willApply(window: 1, current: original)
    #expect(s.takeRestore(window: 1) == original)
    #expect(s.takeRestore(window: 1) == nil)
    s.willApply(window: 2, current: original)
    s.forget(window: 2)
    #expect(s.takeRestore(window: 2) == nil)
}
