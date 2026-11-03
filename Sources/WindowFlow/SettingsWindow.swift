import AppKit
import SwiftUI

enum SettingsTab: Hashable {
    case switcher, shortcuts, general
}

final class SettingsNav: ObservableObject {
    @Published var tab = SettingsTab.switcher
    // Bumped on every language change to rebuild the tab views, which otherwise keep their old strings.
    @Published var languageRevision = 0
}

enum SettingsWindow {
    static let size = NSSize(width: 760, height: 520)
    static var title: String { tr("Settings", "Cài đặt") }

    static func make(settings: Settings, recorder: ShortcutRecorder, nav: SettingsNav, onLanguageChange: @escaping (Language) -> Void) -> NSWindow {
        let root = SettingsRoot(settings: settings, recorder: recorder, nav: nav, onLanguageChange: onLanguageChange)
        let hosting = NSHostingController(rootView: root)
        // Otherwise SwiftUI resizes the window after it is on screen, so it opens off-centre and jumps.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.center()
        return window
    }
}

private struct SettingsRoot: View {
    let settings: Settings
    let recorder: ShortcutRecorder
    @ObservedObject var nav: SettingsNav
    let onLanguageChange: (Language) -> Void

    var body: some View {
        TabView(selection: $nav.tab) {
            SwitcherTab(settings: settings, recorder: recorder)
                .tabItem { Label(tr("Switcher", "Chuyển cửa sổ"), systemImage: "rectangle.on.rectangle") }
                .tag(SettingsTab.switcher)
            ShortcutsTab(settings: settings, recorder: recorder)
                .tabItem { Label(tr("Shortcuts", "Phím tắt"), systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            GeneralTab(onLanguageChange: onLanguageChange)
                .tabItem { Label(tr("General", "Chung"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
        }
        .id(nav.languageRevision)
        .onChange(of: nav.tab) { recorder.cancel() }
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
    }
}
