import Foundation

/// Where the drop zone lives on screen. The notch is the default; the corners
/// exist for setups where another app already owns the notch, which leaves
/// two zones fighting over the same pixels.
enum DropZoneAnchor: String, CaseIterable, Identifiable {
    case notch
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    enum Horizontal {
        case leading
        case center
        case trailing
    }

    var id: String { rawValue }

    /// Anchored to the top edge of the screen — everything but the two
    /// bottom corners.
    var isTop: Bool {
        self != .bottomLeft && self != .bottomRight
    }

    var horizontal: Horizontal {
        switch self {
        case .notch: return .center
        case .topLeft, .bottomLeft: return .leading
        case .topRight, .bottomRight: return .trailing
        }
    }

    var localizedName: String {
        switch self {
        case .notch: return String(localized: "Notch")
        case .topLeft: return String(localized: "Top-left corner")
        case .topRight: return String(localized: "Top-right corner")
        case .bottomLeft: return String(localized: "Bottom-left corner")
        case .bottomRight: return String(localized: "Bottom-right corner")
        }
    }
}
