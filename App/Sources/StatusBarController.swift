import AppKit

/// Discreet menu bar icon. Minimal menu for now: Quit.
@MainActor
final class StatusBarController {
    private let item: NSStatusItem

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "arrow.down.doc",
            accessibilityDescription: "mdNotch"
        )

        let menu = NSMenu()
        let quit = NSMenuItem(
            title: String(localized: "Quit mdNotch"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
        item.menu = menu
    }
}
