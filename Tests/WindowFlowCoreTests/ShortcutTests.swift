import CoreGraphics
import Foundation
import Testing
@testable import WindowFlowCore

@Test func defaultDisplays() {
    #expect(ShortcutDefaults.switcher.display == "⌥⇥")
    #expect(ShortcutDefaults.commandTab.display == "⌘⇥")
    #expect(ShortcutDefaults.actions[.nextDisplay]!.display == "⌃⌥⌘→")
    #expect(ShortcutDefaults.actions[.maximizeHeight]!.display == "⌃⌥⇧↑")
    #expect(ShortcutDefaults.actions[.almostMaximize] == nil)
}

@Test func matchesIgnoresNonModifierBits() {
    let s = ShortcutDefaults.switcher
    let alt: UInt64 = 0x80000
    #expect(s.matches(keyCode: 48, flags: alt | 0x10000 | 0x800000 | 0x200000))
    #expect(!s.matches(keyCode: 48, flags: alt | 0x20000))
    #expect(!s.matches(keyCode: 49, flags: alt))
}

@Test func conflictsAndDefaults() {
    let x = Shortcut(keyCode: 1, modifiers: 0x80000), y = Shortcut(keyCode: 2, modifiers: 0x80000)
    #expect(ShortcutDefaults.conflicts(["a": x, "b": x, "c": y]) == ["a", "b"])
    var all = Dictionary(uniqueKeysWithValues: ShortcutDefaults.actions.map { ($0.key.rawValue, $0.value) })
    all["switcher"] = ShortcutDefaults.switcher
    #expect(ShortcutDefaults.conflicts(all).isEmpty)
}

@Test func shortcutJSONRoundTrip() throws {
    let s = ShortcutDefaults.actions[.center]!
    let back = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(s))
    #expect(back == s)
}

@Test func mergedDefaultsClearedAndOverrides() {
    let custom = Shortcut(keyCode: 0, modifiers: Shortcut.control)
    let merged = ShortcutDefaults.merged(stored: [.leftHalf: custom], cleared: [.rightHalf])
    #expect(merged[.leftHalf] == custom)
    #expect(merged[.rightHalf] == nil)
    #expect(merged[.maximize] == ShortcutDefaults.actions[.maximize])
    #expect(ShortcutDefaults.merged(stored: [:], cleared: []) == ShortcutDefaults.actions)
}

@Test func normalizedDropsNonModifierBits() {
    let s = Shortcut(keyCode: 5, modifiers: Shortcut.option | 0x10000)
    #expect(s.normalized == Shortcut(keyCode: 5, modifiers: Shortcut.option))
}

@Test func diffKeepsOnlyDeviationsFromDefaults() {
    #expect(ShortcutDefaults.diff(ShortcutDefaults.actions).overrides.isEmpty)
    #expect(ShortcutDefaults.diff(ShortcutDefaults.actions).cleared.isEmpty)
    let custom = Shortcut(keyCode: 0, modifiers: Shortcut.control)
    var bindings = ShortcutDefaults.actions
    bindings[.leftHalf] = custom
    bindings[.rightHalf] = nil
    bindings[.almostMaximize] = custom
    let result = ShortcutDefaults.diff(bindings)
    #expect(result.overrides == [.leftHalf: custom, .almostMaximize: custom])
    #expect(result.cleared == [.rightHalf])
    #expect(ShortcutDefaults.merged(stored: result.overrides, cleared: result.cleared) == bindings)
}

@Test func shortcutRules() {
    #expect(!Shortcut(keyCode: 0, modifiers: Shortcut.shift).isAllowed)
    #expect(!Shortcut(keyCode: 0, modifiers: 0).isAllowed)
    #expect(Shortcut(keyCode: 0, modifiers: Shortcut.control).isAllowed)
    #expect(Shortcut(keyCode: 96, modifiers: 0).isAllowed)
    #expect(Shortcut(keyCode: 105, modifiers: Shortcut.shift).isAllowed)
    #expect(Shortcut(keyCode: 90, modifiers: 0).isAllowed)
    #expect(!Shortcut(keyCode: 96, modifiers: 0).isAllowedForSwitcher)
    #expect(!Shortcut(keyCode: 48, modifiers: Shortcut.shift).isAllowedForSwitcher)
    #expect(ShortcutDefaults.switcher.isAllowedForSwitcher)
    #expect(Shortcut(keyCode: 105, modifiers: 0).display == "F13")
}
