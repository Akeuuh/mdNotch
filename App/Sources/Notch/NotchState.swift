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
    }

    @Published var phase: Phase = .idle
}
