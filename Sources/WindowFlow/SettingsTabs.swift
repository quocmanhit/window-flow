import AppKit
import ApplicationServices
import Combine
import SwiftUI
import WindowFlowCore

private func conflictingNames(_ settings: Settings) -> Set<String> {
    var all = Dictionary(uniqueKeysWithValues: settings.shortcuts.map { ($0.key.rawValue, $0.value.normalized) })
    all[switcherID] = settings.switcherShortcut.normalized
    return ShortcutDefaults.conflicts(all)
}

private let switcherID = "switcher"

struct SwitcherTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject var recorder: ShortcutRecorder

    private var isCommandTab: Bool { settings.switcherShortcut.normalized == ShortcutDefaults.commandTab }

    var body: some View {
        Form {
            Section(tr("Shortcut", "Phím tắt")) {
                LabeledContent(tr("Switch windows", "Chuyển cửa sổ")) {
                    ShortcutField(
                        id: switcherID, shortcut: settings.switcherShortcut,
                        conflict: conflictingNames(settings).contains(switcherID), forSwitcher: true, recorder: recorder
                    ) { settings.switcherShortcut = $0 }
                }
                if let notice = recorder.notice(for: switcherID) {
                    Text(notice).foregroundStyle(.red)
                }
                HStack {
                    Button("⌥Tab") { settings.switcherShortcut = ShortcutDefaults.switcher }
                    Button(tr("⌘Tab (replaces the macOS app switcher)", "⌘Tab (thay bộ chuyển app của macOS)")) {
                        settings.switcherShortcut = ShortcutDefaults.commandTab
                    }
                }
            }
            Section(tr("Windows to list", "Cửa sổ hiển thị")) {
                Toggle(tr("Include minimized windows", "Gồm cả cửa sổ đã thu nhỏ"), isOn: Binding(
                    get: { settings.includeMinimized }, set: { settings.includeMinimized = $0 }))
                Toggle(tr("Include windows from all Spaces", "Gồm cả cửa sổ ở mọi Space"), isOn: Binding(
                    get: { settings.allSpaces }, set: { settings.allSpaces = $0 }))
            }
            Section {
                Toggle(
                    tr("Also turn off the macOS ⌘Tab switcher (use if ⌘Tab still shows the system switcher)",
                       "Tắt luôn bộ chuyển app ⌘Tab của macOS (dùng nếu ⌘Tab vẫn hiện bộ chuyển của hệ thống)"),
                    isOn: Binding(get: { settings.disableSystemCommandTab }, set: { settings.disableSystemCommandTab = $0 })
                )
                .disabled(!isCommandTab)
            } footer: {
                if !isCommandTab {
                    Text(tr("Available when the switcher shortcut is ⌘Tab.", "Chỉ dùng được khi phím tắt chuyển cửa sổ là ⌘Tab."))
                }
            }
        }
        .formStyle(.grouped)
    }
}

private var actionGroups: [(title: String, actions: [WindowAction])] {
    [
        (tr("Halves", "Một nửa"), [.leftHalf, .rightHalf, .topHalf, .bottomHalf]),
        (tr("Quarters", "Một phần tư"), [.topLeft, .topRight, .bottomLeft, .bottomRight]),
        (tr("Thirds", "Một phần ba"), [.firstThird, .centerThird, .lastThird]),
        (tr("Two-thirds", "Hai phần ba"), [.firstTwoThirds, .lastTwoThirds]),
        (tr("Maximize", "Phóng to"), [.maximize, .almostMaximize, .maximizeHeight]),
        (tr("Size", "Kích thước"), [.larger, .smaller]),
        (tr("Center and restore", "Căn giữa và khôi phục"), [.center, .restore]),
        (tr("Displays", "Màn hình"), [.nextDisplay, .previousDisplay]),
    ]
}

struct ShortcutsTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject var recorder: ShortcutRecorder

    var body: some View {
        let conflicts = conflictingNames(settings)
        Form {
            Section {
                LabeledContent(tr("Gap between windows", "Khoảng hở giữa các cửa sổ")) {
                    HStack {
                        Slider(value: Binding(get: { settings.gap }, set: { settings.gap = $0 }), in: 0...30, step: 1)
                            .frame(width: 220)
                        Text("\(Int(settings.gap)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }
            ForEach(actionGroups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.actions, id: \.self) { action in row(action, conflict: conflicts.contains(action.rawValue)) }
                }
            }
            Section {
                Button(tr("Restore default shortcuts", "Khôi phục phím tắt mặc định")) {
                    recorder.cancel()
                    settings.restoreDefaultShortcuts()
                }
                .help(tr("Resets the window shortcuts only; the switcher shortcut is not changed.",
                         "Chỉ đặt lại phím tắt cửa sổ; phím tắt chuyển cửa sổ không đổi."))
            } footer: {
                Text(tr("The switcher shortcut is not changed.", "Phím tắt chuyển cửa sổ không bị đổi."))
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ action: WindowAction, conflict: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(action.title).foregroundStyle(conflict ? Color.red : Color.primary)
                Spacer()
                ShortcutField(id: action.rawValue, shortcut: settings.shortcuts[action], conflict: conflict, recorder: recorder) {
                    set(action, $0)
                }
                Button {
                    recorder.cancel()
                    set(action, nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(settings.shortcuts[action] == nil)
                .help(tr("Clear shortcut", "Xoá phím tắt"))
            }
            if let notice = recorder.notice(for: action.rawValue) {
                Text(notice).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func set(_ action: WindowAction, _ shortcut: Shortcut?) {
        var next = settings.shortcuts
        next[action] = shortcut
        settings.shortcuts = next
    }
}

struct GeneralTab: View {
    let onLanguageChange: (Language) -> Void
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var trusted = AXIsProcessTrusted()
    // The state can also change from the menu or System Settings while this window is open.
    private let refresh = NotificationCenter.default.publisher(for: LaunchAtLogin.didChange)
        .merge(with: NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))

    var body: some View {
        Form {
            Picker(tr("Language", "Ngôn ngữ"), selection: Binding(get: { Language.current }, set: onLanguageChange)) {
                ForEach(Language.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Toggle(tr("Launch at login", "Mở cùng macOS"), isOn: Binding(
                get: { launchAtLogin },
                set: {
                    LaunchAtLogin.set($0)
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
            ))
            LabeledContent(tr("Accessibility", "Quyền Accessibility")) {
                HStack {
                    Text(trusted ? tr("Granted", "Đã cấp") : tr("Not granted", "Chưa cấp"))
                        .foregroundStyle(trusted ? Color.green : Color.red)
                    Button(tr("Open System Settings…", "Mở Cài đặt hệ thống…")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshState() }
        .onReceive(refresh) { _ in refreshState() }
    }

    private func refreshState() {
        launchAtLogin = LaunchAtLogin.isEnabled
        trusted = AXIsProcessTrusted()
    }
}
