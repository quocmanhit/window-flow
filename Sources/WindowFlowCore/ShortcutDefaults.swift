public enum ShortcutDefaults {
    private static let co = Shortcut.control | Shortcut.option

    public static let switcher = Shortcut(keyCode: 48, modifiers: Shortcut.option)
    public static let commandTab = Shortcut(keyCode: 48, modifiers: Shortcut.command)

    public static let actions: [WindowAction: Shortcut] = [
        .leftHalf: Shortcut(keyCode: 123, modifiers: co),
        .rightHalf: Shortcut(keyCode: 124, modifiers: co),
        .topHalf: Shortcut(keyCode: 126, modifiers: co),
        .bottomHalf: Shortcut(keyCode: 125, modifiers: co),
        .topLeft: Shortcut(keyCode: 32, modifiers: co),
        .topRight: Shortcut(keyCode: 34, modifiers: co),
        .bottomLeft: Shortcut(keyCode: 38, modifiers: co),
        .bottomRight: Shortcut(keyCode: 40, modifiers: co),
        .firstThird: Shortcut(keyCode: 2, modifiers: co),
        .centerThird: Shortcut(keyCode: 3, modifiers: co),
        .lastThird: Shortcut(keyCode: 5, modifiers: co),
        .firstTwoThirds: Shortcut(keyCode: 14, modifiers: co),
        .lastTwoThirds: Shortcut(keyCode: 17, modifiers: co),
        .maximize: Shortcut(keyCode: 36, modifiers: co),
        .maximizeHeight: Shortcut(keyCode: 126, modifiers: co | Shortcut.shift),
        .toggleMaximize: Shortcut(keyCode: 36, modifiers: co | Shortcut.command),
        .larger: Shortcut(keyCode: 24, modifiers: co),
        .smaller: Shortcut(keyCode: 27, modifiers: co),
        .center: Shortcut(keyCode: 8, modifiers: co),
        .restore: Shortcut(keyCode: 51, modifiers: co),
        .nextDisplay: Shortcut(keyCode: 124, modifiers: co | Shortcut.command),
        .previousDisplay: Shortcut(keyCode: 123, modifiers: co | Shortcut.command),
    ]

    /// Defaults, minus explicitly cleared actions, overridden by stored ones; actions in neither set keep their default.
    public static func merged(stored: [WindowAction: Shortcut], cleared: Set<WindowAction>) -> [WindowAction: Shortcut] {
        var result = actions
        for action in cleared { result[action] = nil }
        for (action, shortcut) in stored { result[action] = shortcut }
        return result
    }

    /// Only what differs from the defaults: changed or new shortcuts, and defaults the user cleared.
    public static func diff(_ bindings: [WindowAction: Shortcut]) -> (overrides: [WindowAction: Shortcut], cleared: Set<WindowAction>) {
        var overrides: [WindowAction: Shortcut] = [:]
        var cleared = Set<WindowAction>()
        for action in WindowAction.allCases {
            switch (bindings[action], actions[action]) {
            case let (bound?, standard) where bound != standard: overrides[action] = bound
            case (nil, _?): cleared.insert(action)
            default: break
            }
        }
        return (overrides, cleared)
    }

    /// Names whose shortcut is also bound to another name.
    public static func conflicts(_ bindings: [String: Shortcut]) -> Set<String> {
        var byShortcut: [Shortcut: [String]] = [:]
        for (name, s) in bindings { byShortcut[s, default: []].append(name) }
        return Set(byShortcut.values.filter { $0.count > 1 }.flatMap { $0 })
    }
}
