import CoreGraphics
import Testing
@testable import WindowFlowCore

private let full = CGRect(x: 0, y: 25, width: 1440, height: 875)
private let small = CGRect(x: 100, y: 100, width: 600, height: 400)

@Test func zoomMaximizesThenReturnsToThePreviousFrame() {
    var z = ZoomToggle()
    #expect(z.step(window: 1, current: small, maximized: full) == .maximize)
    z.didZoom(window: 1, to: full)
    #expect(z.step(window: 1, current: full, maximized: full) == .restore(small))
    #expect(z.step(window: 1, current: small, maximized: full) == .maximize)
}

@Test func zoomBackWorksForAnAppThatRefusedTheFullSize() {
    var z = ZoomToggle()
    let capped = CGRect(x: 0, y: 25, width: 1200, height: 875)
    _ = z.step(window: 1, current: small, maximized: full)
    z.didZoom(window: 1, to: capped)
    #expect(z.step(window: 1, current: capped, maximized: full) == .restore(small))
}

@Test func windowMovedAfterZoomIsZoomedAgainFromItsNewFrame() {
    var z = ZoomToggle()
    _ = z.step(window: 1, current: small, maximized: full)
    z.didZoom(window: 1, to: full)
    let moved = CGRect(x: 300, y: 200, width: 800, height: 500)
    #expect(z.step(window: 1, current: moved, maximized: full) == .maximize)
    z.didZoom(window: 1, to: full)
    #expect(z.step(window: 1, current: full, maximized: full) == .restore(moved))
}

@Test func alreadyMaximizedWindowFallsBackToOriginalRestore() {
    var z = ZoomToggle()
    #expect(z.step(window: 2, current: full, maximized: full) == .restoreOriginal)
}

@Test func windowsAreIndependent() {
    var z = ZoomToggle()
    _ = z.step(window: 1, current: small, maximized: full)
    z.didZoom(window: 1, to: full)
    #expect(z.step(window: 2, current: small, maximized: full) == .maximize)
    #expect(z.step(window: 1, current: full, maximized: full) == .restore(small))
}

@Test func toggleMaximizeHasItsOwnDefaultShortcut() {
    #expect(ShortcutDefaults.actions[.toggleMaximize]!.display == "⌃⌥⌘↩")
    #expect(ShortcutDefaults.conflicts(Dictionary(uniqueKeysWithValues: ShortcutDefaults.actions.map { ($0.key.rawValue, $0.value) })).isEmpty)
}
