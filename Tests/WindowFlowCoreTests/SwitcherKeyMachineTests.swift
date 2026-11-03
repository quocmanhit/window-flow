import CoreGraphics
import Testing
@testable import WindowFlowCore

private let option = Shortcut.option, shift = Shortcut.shift, command = Shortcut.command
private let tab: UInt16 = 48

private func machine(_ s: Shortcut = ShortcutDefaults.switcher) -> SwitcherKeyMachine { SwitcherKeyMachine(shortcut: s) }

@Test func opensOnShortcutAndSwallows() {
    var m = machine()
    let r = m.handle(type: .keyDown, keyCode: tab, flags: option)
    #expect(r.swallow)
    #expect(r.commands == [SwitcherCommand(session: 1, action: .open(reverse: false))])
    #expect(m.isActive)
}

@Test func ignoresOtherKeysAndMissingModifier() {
    var m = machine()
    #expect(!m.handle(type: .keyDown, keyCode: tab, flags: 0).swallow)
    #expect(!m.handle(type: .keyDown, keyCode: 0, flags: option).swallow)
    #expect(!m.handle(type: .keyDown, keyCode: tab, flags: option | command).swallow)
    #expect(!m.isActive)
}

@Test func shiftOpensReverseAndMovesBack() {
    var m = machine()
    #expect(m.handle(type: .keyDown, keyCode: tab, flags: option | shift).commands.first?.action == .open(reverse: true))
    #expect(m.handle(type: .keyDown, keyCode: tab, flags: option | shift).commands.first?.action == .previous)
    #expect(m.handle(type: .keyDown, keyCode: tab, flags: option).commands.first?.action == .next)
}

@Test func arrowsMoveAndOtherKeysAreSwallowedWhileOpen() {
    var m = machine()
    _ = m.handle(type: .keyDown, keyCode: tab, flags: option)
    #expect(m.handle(type: .keyDown, keyCode: 124, flags: option).commands.first?.action == .next)
    #expect(m.handle(type: .keyDown, keyCode: 123, flags: option).commands.first?.action == .previous)
    let other = m.handle(type: .keyDown, keyCode: 0, flags: option)
    #expect(other.swallow && other.commands.isEmpty)
    #expect(m.handle(type: .keyUp, keyCode: 0, flags: option).swallow)
}

@Test func escapeCancelsAndItsKeyUpIsSwallowed() {
    var m = machine()
    _ = m.handle(type: .keyDown, keyCode: tab, flags: option)
    let r = m.handle(type: .keyDown, keyCode: 53, flags: option)
    #expect(r.swallow && r.commands == [SwitcherCommand(session: 1, action: .cancel)])
    #expect(!m.isActive)
    #expect(m.handle(type: .keyUp, keyCode: 53, flags: option).swallow)
    #expect(!m.handle(type: .keyUp, keyCode: 53, flags: option).swallow)
}

@Test func returnCommits() {
    var m = machine()
    _ = m.handle(type: .keyDown, keyCode: tab, flags: option)
    #expect(m.handle(type: .keyDown, keyCode: 36, flags: option).commands.first?.action == .commit)
    #expect(!m.isActive)
}

@Test func releasingTheModifierCommitsAndPassesTheEvent() {
    var m = machine()
    _ = m.handle(type: .keyDown, keyCode: tab, flags: option)
    let r = m.handle(type: .flagsChanged, keyCode: 58, flags: 0)
    #expect(!r.swallow)
    #expect(r.commands == [SwitcherCommand(session: 1, action: .commit)])
    #expect(!m.isActive)
}

@Test func tabKeyUpIsSwallowedAfterQuickTap() {
    var m = machine()
    _ = m.handle(type: .keyDown, keyCode: tab, flags: option)
    _ = m.handle(type: .flagsChanged, keyCode: 58, flags: 0)
    #expect(m.handle(type: .keyUp, keyCode: tab, flags: 0).swallow)
}

@Test func keyDownWithoutModifierWhileOpenCommitsThenBehavesNormally() {
    var m = machine()
    _ = m.handle(type: .keyDown, keyCode: tab, flags: option)
    let r = m.handle(type: .keyDown, keyCode: 0, flags: 0)
    #expect(!r.swallow)
    #expect(r.commands == [SwitcherCommand(session: 1, action: .commit)])
    #expect(!m.isActive)
}

@Test func reconcileAndReenableCommitOnlyWhenModifierLost() {
    var m = machine()
    #expect(m.reconcile(flags: 0).isEmpty)
    _ = m.handle(type: .keyDown, keyCode: tab, flags: option)
    #expect(m.reconcile(flags: option).isEmpty)
    #expect(m.tapReenabled(flags: option | 0x100).isEmpty)
    #expect(m.tapReenabled(flags: 0) == [SwitcherCommand(session: 1, action: .commit)])
    #expect(!m.isActive)
}

@Test func closeEndsOnlyTheMatchingSession() {
    var m = machine()
    _ = m.handle(type: .keyDown, keyCode: tab, flags: option)
    m.close(session: 5)
    #expect(m.isActive)
    m.close(session: 1)
    #expect(!m.isActive)
    #expect(m.handle(type: .keyDown, keyCode: tab, flags: option).commands.first?.session == 2)
}

@Test func commandTabAndModifierlessShortcut() {
    var cmd = machine(ShortcutDefaults.commandTab)
    #expect(cmd.handle(type: .keyDown, keyCode: tab, flags: command).swallow)
    var none = machine(Shortcut(keyCode: tab, modifiers: 0))
    #expect(!none.handle(type: .keyDown, keyCode: tab, flags: 0).swallow)
}
