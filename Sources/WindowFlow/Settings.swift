import Foundation
import WindowFlowCore

final class Settings: ObservableObject {
    private let defaults = UserDefaults.standard

    // Cached so the tap's lookup table can be rebuilt without re-decoding.
    private var bindings: [WindowAction: Shortcut]
    var onShortcutsChanged: () -> Void = {}
    var onRecordingChanged: (Bool) -> Void = { _ in }

    /// Not published: only the key tap needs it, to ignore shortcuts while a recorder captures one.
    func setRecording(_ recording: Bool) { onRecordingChanged(recording) }

    init() {
        let decoder = JSONDecoder()
        let overrides = defaults.data(forKey: Key.overrides)
            .flatMap { try? decoder.decode([String: Shortcut].self, from: $0) } ?? [:]
        let cleared = defaults.stringArray(forKey: Key.cleared) ?? []
        bindings = ShortcutDefaults.merged(
            stored: Dictionary(uniqueKeysWithValues: overrides.compactMap { key, value in
                WindowAction(rawValue: key).map { ($0, value) }
            }),
            cleared: Set(cleared.compactMap(WindowAction.init(rawValue:))))
        defaults.removeObject(forKey: "snapEnabled")  // drag-to-snap was removed
        defaults.register(defaults: [
            Key.gap: 0.0, Key.includeMinimized: true, Key.allSpaces: true,
            Key.switcherOpacity: 0.0, Key.switcherOnMainDisplay: true,
        ])
    }

    // Cleared defaults are stored explicitly so actions added by a later version still get their default.
    var shortcuts: [WindowAction: Shortcut] {
        get { bindings }
        set {
            objectWillChange.send()
            bindings = newValue
            let diff = ShortcutDefaults.diff(newValue)
            let overrides = Dictionary(uniqueKeysWithValues: diff.overrides.map { ($0.key.rawValue, $0.value) })
            defaults.set(try? JSONEncoder().encode(overrides), forKey: Key.overrides)
            defaults.set(WindowAction.allCases.filter(diff.cleared.contains).map(\.rawValue), forKey: Key.cleared)
            onShortcutsChanged()
        }
    }

    func restoreDefaultShortcuts() {
        objectWillChange.send()
        bindings = ShortcutDefaults.actions
        defaults.removeObject(forKey: Key.overrides)
        defaults.removeObject(forKey: Key.cleared)
        onShortcutsChanged()
    }

    var switcherShortcut: Shortcut {
        get {
            guard let data = defaults.data(forKey: Key.switcher),
                  let value = try? JSONDecoder().decode(Shortcut.self, from: data) else { return ShortcutDefaults.switcher }
            return value
        }
        set {
            objectWillChange.send()
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.switcher)
        }
    }

    var gap: Double {
        get { min(max(defaults.double(forKey: Key.gap), 0), 30) }
        set { objectWillChange.send(); defaults.set(min(max(newValue, 0), 30), forKey: Key.gap) }
    }

    var includeMinimized: Bool {
        get { defaults.bool(forKey: Key.includeMinimized) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.includeMinimized) }
    }

    var allSpaces: Bool {
        get { defaults.bool(forKey: Key.allSpaces) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.allSpaces) }
    }

    /// Off: the switcher opens on the display under the pointer.
    var switcherOnMainDisplay: Bool {
        get { defaults.bool(forKey: Key.switcherOnMainDisplay) }
        set { objectWillChange.send(); defaults.set(newValue, forKey: Key.switcherOnMainDisplay) }
    }

    var switcherAppearance: SwitcherAppearance {
        get {
            SwitcherAppearance(
                size: defaults.string(forKey: Key.switcherSize).flatMap(SwitcherSize.init(rawValue:)) ?? .large,
                titles: defaults.string(forKey: Key.switcherTitles).flatMap(SwitcherTitles.init(rawValue:))
                    // Earlier builds stored a plain on/off; off now means the selected window's title only.
                    ?? (defaults.object(forKey: Key.switcherShowTitles) as? Bool == true ? .all : .selected),
                background: defaults.string(forKey: Key.switcherBackground).flatMap(SwitcherBackground.init(rawValue:)) ?? .glass,
                highlight: defaults.string(forKey: Key.switcherHighlight).flatMap(SwitcherHighlight.init(rawValue:)) ?? .neutral,
                opacity: defaults.double(forKey: Key.switcherOpacity))
        }
        set {
            objectWillChange.send()
            defaults.set(newValue.size.rawValue, forKey: Key.switcherSize)
            defaults.set(newValue.titles.rawValue, forKey: Key.switcherTitles)
            defaults.removeObject(forKey: Key.switcherShowTitles)
            defaults.set(newValue.background.rawValue, forKey: Key.switcherBackground)
            defaults.set(newValue.highlight.rawValue, forKey: Key.switcherHighlight)
            defaults.set(newValue.opacity, forKey: Key.switcherOpacity)
        }
    }

    var disableSystemCommandTab: Bool {
        get { SystemSwitcherHotKey.fallbackEnabled }
        set { objectWillChange.send(); SystemSwitcherHotKey.fallbackEnabled = newValue }
    }

    private enum Key {
        static let overrides = "shortcutOverrides"
        static let cleared = "shortcutCleared"
        static let switcher = "switcherShortcut"
        static let gap = "gap"
        static let includeMinimized = "includeMinimized"
        static let allSpaces = "allSpaces"
        static let switcherOnMainDisplay = "switcherOnMainDisplay"
        static let switcherSize = "switcherSize"
        static let switcherShowTitles = "switcherShowTitles"
        static let switcherTitles = "switcherTitles"
        static let switcherBackground = "switcherBackground"
        static let switcherHighlight = "switcherHighlight"
        static let switcherOpacity = "switcherOpacity"
    }
}
