import AppKit

/// Which displays the drop zone answers on. `all` by default — a drag is
/// caught on whichever screen it happens. `main` keeps it on the primary
/// display only, and `display` pins it to one chosen monitor, for setups
/// where the zone is only ever wanted in one place.
enum DropZoneScreens: Hashable, Identifiable {
    case all
    case main
    /// A specific monitor. The name is kept next to the ID because display
    /// IDs are reassigned across reboots and re-plugs, and would silently
    /// point at the wrong monitor — or none.
    case display(id: CGDirectDisplayID, name: String)

    var id: String { rawValue }

    // MARK: - Persistence

    var rawValue: String {
        switch self {
        case .all: return "all"
        case .main: return "main"
        case .display(let id, let name): return "display:\(id):\(name)"
        }
    }

    init?(rawValue: String) {
        switch rawValue {
        case "all":
            self = .all
        case "main":
            self = .main
        default:
            // Names can contain colons, so only the first two are separators.
            let parts = rawValue.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "display", let id = CGDirectDisplayID(parts[1]) else {
                return nil
            }
            self = .display(id: id, name: String(parts[2]))
        }
    }

    // MARK: - Resolution

    /// The single screen the zone is restricted to; nil when every screen is
    /// allowed.
    var pinnedScreen: NSScreen? {
        switch self {
        case .all:
            return nil
        case .main:
            return Self.primaryScreen
        case .display(let id, let name):
            if let byID = NSScreen.screens.first(where: { $0.displayID == id }) { return byID }
            // Same monitor, new ID after a re-plug: match on its name.
            if let byName = NSScreen.screens.first(where: { $0.localizedName == name }) { return byName }
            // The monitor is gone. Falling back to the primary display keeps
            // the app usable instead of making it look broken.
            return Self.primaryScreen
        }
    }

    /// Whether the zone may come out on `screen`.
    func includes(_ screen: NSScreen) -> Bool {
        guard let pinned = pinnedScreen else { return true }
        return pinned.displayID == screen.displayID
    }

    /// Screen the zone should appear on when nothing points at one — a
    /// clipboard conversion has no drag to follow. Unrestricted, that is the
    /// screen the user is working on: the one under the pointer.
    func targetScreen(mouseAt mouse: NSPoint = NSEvent.mouseLocation) -> NSScreen? {
        if let pinned = pinnedScreen { return pinned }
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? Self.primaryScreen
    }

    /// Display holding the menu bar, i.e. the origin of the global coordinate
    /// space. Deliberately not `NSScreen.main`, which follows the focused
    /// window and so moves from one display to another.
    static var primaryScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
    }

    // MARK: - Settings UI

    /// Choices to offer right now: the two modes plus every connected
    /// display.
    static var available: [DropZoneScreens] {
        [.all, .main] + NSScreen.screens.map { .display(id: $0.displayID, name: $0.localizedName) }
    }

    var localizedName: String {
        switch self {
        case .all: return String(localized: "All screens")
        case .main: return String(localized: "Main screen only")
        case .display(_, let name): return name
        }
    }
}

extension NSScreen {
    /// `CGDirectDisplayID` of this screen, the only identity that survives
    /// `NSScreen` instances being recreated on a display change.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
