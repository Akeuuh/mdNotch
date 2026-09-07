import Foundation

/// Observable UI state of the notch zone. The UI layer renders this and does
/// nothing else; behavior lives behind it.
@MainActor
final class NotchState: ObservableObject {
    enum Phase: Equatable {
        /// Nothing on screen.
        case idle
        /// A file drag is near the top-center: the drop zone is extended.
        /// `hovering` is true while the drag is directly over the zone.
        case dropTarget(hovering: Bool)
        /// Files were dropped, conversion is running (spinner + glow).
        case converting
        /// Conversion succeeded: green check + a short claim ("Copied", or
        /// "Copied as-is" when nothing needed converting), then auto-collapse.
        case success(message: String)
        /// At least one file failed: red cross + short message(s).
        /// Collapses on click or after ~4 s.
        case failure(message: String)
        /// Mouse hovers the notch area: compact bar with the settings gear.
        case settingsHover
    }

    @Published var phase: Phase = .idle

    /// Screen edge the zone hangs from. Drives its shape, its padding and the
    /// direction it slides in from.
    @Published var anchor: DropZoneAnchor = .notch

    /// Height of the notch the zone hangs from. Content is pushed below it:
    /// anything drawn inside the notch is invisible. Zero for corner anchors,
    /// which hide nothing.
    @Published var topInset: CGFloat = 0

    /// Footprint the zone grows out of and shrinks back into: the physical
    /// notch itself, so extending reads as the cutout widening rather than as
    /// a panel sliding down over the screen.
    @Published var collapsedSize: CGSize = .zero

    /// Footprint of the zone once out.
    @Published var expandedSize: CGSize = .zero

    /// Whether the zone is extended. Everything but the two resting states,
    /// which sit at `collapsedSize` and are not drawn.
    var isExtended: Bool {
        switch phase {
        case .idle, .settingsHover: return false
        case .dropTarget, .converting, .success, .failure: return true
        }
    }
}
