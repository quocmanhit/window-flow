import CoreGraphics

public struct Shortcut: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    static let modifierMask: UInt64 = Shortcut.control | Shortcut.option | Shortcut.shift | Shortcut.command
    static let control: UInt64 = CGEventFlags.maskControl.rawValue
    static let option: UInt64 = CGEventFlags.maskAlternate.rawValue
    static let shift: UInt64 = CGEventFlags.maskShift.rawValue
    static let command: UInt64 = CGEventFlags.maskCommand.rawValue

    public var display: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    /// The shortcut with only the ⌃⌥⇧⌘ bits kept, usable as a lookup key for a pressed key.
    public var normalized: Shortcut { Shortcut(keyCode: keyCode, modifiers: modifiers & Self.modifierMask) }

    public func matches(keyCode: UInt16, flags: UInt64) -> Bool {
        keyCode == self.keyCode && flags & Self.modifierMask == modifiers & Self.modifierMask
    }

    private static let modifiersForShortcut: UInt64 = control | option | command
    // F1–F20 key codes.
    private static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

    /// Needs ⌃, ⌥ or ⌘ (⇧ alone would swallow capital letters), except F1–F20 which may be bare.
    public var isAllowed: Bool { Self.functionKeys.contains(keyCode) || modifiers & Self.modifiersForShortcut != 0 }

    /// The switcher must hold its modifier while cycling, so F-keys get no exemption.
    public var isAllowedForSwitcher: Bool { modifiers & Self.modifiersForShortcut != 0 }

    // ANSI layout virtual key codes; enough to label any shortcut.
    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]
}
