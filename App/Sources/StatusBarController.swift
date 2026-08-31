import AppKit

/// Discreet menu bar icon. Minimal menu for now: Quit.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let settings: AppSettings
    private let onSettings: () -> Void
    private let loginItem: NSMenuItem

    init(settings: AppSettings, onSettings: @escaping () -> Void) {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.settings = settings
        self.onSettings = onSettings
        self.loginItem = NSMenuItem(
            title: String(localized: "Launch at login"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        super.init()

        item.button?.image = NSImage(
            systemSymbolName: "arrow.down.doc",
            accessibilityDescription: "mdNotch"
        )

        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(localized: "Quit mdNotch"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
        item.menu = menu
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            loginItem.state = settings.launchAtLogin ? .on : .off
        }
    }

    @objc private func openSettings() {
        onSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        settings.launchAtLogin.toggle()
    }
}
