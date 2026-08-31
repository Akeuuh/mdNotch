import AppKit

/// Watches global mouse moves and reports when the pointer is over the
/// notch area (settings gear reveal).
@MainActor
final class HoverMonitor {
    var onHoverChanged: ((_ inside: Bool, _ screen: NSScreen?) -> Void)?

    private var monitors: [Any] = []
    private var wasInside = false

    func start() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            self?.handleMove()
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            self?.handleMove()
            return event
        }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor(_:))
        monitors.removeAll()
    }

    private func handleMove() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        let inside = screen.map { NSMouseInRect(mouse, NotchGeometry.hoverRegion(on: $0), false) } ?? false
        guard inside != wasInside else { return }
        wasInside = inside
        onHoverChanged?(inside, screen)
    }
}
