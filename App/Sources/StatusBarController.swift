import AppKit

/// Discreet menu bar icon. Minimal menu for now: Quit.
@MainActor
final class StatusBarController: NSObject {
    private let item: NSStatusItem
    private let onSettings: () -> Void

    init(onSettings: @escaping () -> Void) {
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.onSettings = onSettings
        super.init()

        item.button?.image = NSImage(
            systemSymbolName: "arrow.down.doc",
            accessibilityDescription: "mdNotch"
        )

        let menu = NSMenu()

        let settings = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(localized: "Quit mdNotch"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
        item.menu = menu
    }

    @objc private func openSettings() {
        onSettings()
    }
}
