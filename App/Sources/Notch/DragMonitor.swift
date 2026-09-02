import AppKit

/// Watches global mouse drags and reports when a *convertible* drag is near
/// the trigger region of a screen. Uses the drag pasteboard's change count to
/// spot the start of each drag session, then its types to decide whether the
/// zone should come out at all.
@MainActor
final class DragMonitor {
    /// Where the drop zone currently lives; sets the trigger region.
    var anchor: DropZoneAnchor = .notch

    /// Called on every relevant drag move: is the drag inside the trigger
    /// region, and on which screen.
    var onUpdate: ((_ nearTarget: Bool, _ screen: NSScreen?) -> Void)?
    /// Called when the mouse button is released during a convertible drag
    /// (wherever it happens — a drop on our own window arrives through
    /// NSDraggingDestination separately).
    var onDragEnded: (() -> Void)?

    /// Types worth revealing the zone for. Plain strings are excluded: they
    /// need no conversion, and including them would pop the zone out every
    /// time a sentence is dragged around inside an editor.
    private static let triggerTypes: [NSPasteboard.PasteboardType] = [.fileURL, .html, .rtf]

    private var monitors: [Any] = []
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var sessionChangeCount: Int
    private var payloadDragActive = false

    init() {
        sessionChangeCount = dragPasteboard.changeCount
    }

    func start() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            self?.handleDragged()
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            self?.handleUp()
        }) { monitors.append(m) }

        // Global monitors do not see this app's own events.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            if event.type == .leftMouseDragged {
                self?.handleDragged()
            } else {
                self?.handleUp()
            }
            return event
        }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor(_:))
        monitors.removeAll()
    }

    private func handleDragged() {
        if dragPasteboard.changeCount != sessionChangeCount {
            // A new drag session started; check whether it carries anything
            // we can convert.
            sessionChangeCount = dragPasteboard.changeCount
            payloadDragActive = dragPasteboard.availableType(from: Self.triggerTypes) != nil
        }
        guard payloadDragActive else { return }

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else {
            onUpdate?(false, nil)
            return
        }
        let near = NSMouseInRect(mouse, NotchGeometry.triggerRegion(for: anchor, on: screen), false)
        onUpdate?(near, screen)
    }

    private func handleUp() {
        guard payloadDragActive else { return }
        payloadDragActive = false
        onDragEnded?()
    }
}
