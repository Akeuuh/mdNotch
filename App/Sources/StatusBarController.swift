import AppKit

/// Discreet menu bar icon: convert the clipboard, settings, launch at login,
/// quit.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let settings: AppSettings
    private let onSettings: () -> Void
    private let onConvertClipboard: () -> Void
    private let loginItem: NSMenuItem
    private let clipboardItem: NSMenuItem

    init(
        settings: AppSettings,
        onSettings: @escaping () -> Void,
        onConvertClipboard: @escaping () -> Void
    ) {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.settings = settings
        self.onSettings = onSettings
        self.onConvertClipboard = onConvertClipboard
        self.loginItem = NSMenuItem(
            title: String(localized: "Launch at login"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        self.clipboardItem = NSMenuItem(
            title: String(localized: "Convert clipboard"),
            action: #selector(convertClipboard),
            keyEquivalent: ""
        )
        super.init()

        item.button?.image = NSImage(
            systemSymbolName: "arrow.down.doc",
            accessibilityDescription: "mdNotch"
        )

        let menu = NSMenu()
        menu.delegate = self

        clipboardItem.target = self
        menu.addItem(clipboardItem)

        menu.addItem(.separator())

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
            // The menu doubles as documentation for the configured shortcut,
            // so it must not keep showing a stale one.
            if let combo = settings.pasteHotKey, let key = combo.menuKeyEquivalent {
                clipboardItem.keyEquivalent = key
                clipboardItem.keyEquivalentModifierMask = combo.modifiers
            } else {
                clipboardItem.keyEquivalent = ""
                clipboardItem.keyEquivalentModifierMask = []
            }
        }
    }

    @objc private func openSettings() {
        onSettings()
    }

    @objc private func convertClipboard() {
        onConvertClipboard()
    }

    @objc private func toggleLaunchAtLogin() {
        settings.launchAtLogin.toggle()
    }
}
