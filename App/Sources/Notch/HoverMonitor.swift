import AppKit

/// Reports global mouse moves. The controller decides what counts as
/// hovering the notch, since the region it must stay inside grows once the
/// settings gear is out.
@MainActor
final class HoverMonitor {
    var onMouseMoved: ((_ location: NSPoint, _ screen: NSScreen?) -> Void)?

    private var monitors: [Any] = []

    func start() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            self?.handleMove()
        }) { monitors.append(m) }

        // Global monitors do not see this app's own events.
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
        onMouseMoved?(mouse, screen)
    }
}
