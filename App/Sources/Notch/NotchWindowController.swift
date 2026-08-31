import AppKit
import SwiftUI

/// Borderless always-on-top panel anchored under the notch (or top-center on
/// screens without one). Invisible at rest; extends when a file drag comes
/// near; accepts drops and hands the URLs to `onFilesDropped`.
@MainActor
final class NotchWindowController {
    let state = NotchState()
    var onFilesDropped: (([URL]) -> Void)?

    private let panel: NSPanel
    private let dragMonitor = DragMonitor()

    init() {
        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false

        let dropView = DropView(frame: .zero)
        dropView.onDragEntered = { [weak self] in
            self?.state.phase = .dropTarget(hovering: true)
        }
        dropView.onDragExited = { [weak self] in
            self?.state.phase = .dropTarget(hovering: false)
        }
        dropView.onFilesDropped = { [weak self] urls in
            self?.handleDrop(urls)
        }

        let hosting = NSHostingView(rootView: NotchView(state: state))
        hosting.autoresizingMask = [.width, .height]
        dropView.addSubview(hosting)
        panel.contentView = dropView
        hosting.frame = dropView.bounds
    }

    func start() {
        dragMonitor.onUpdate = { [weak self] near, screen in
            self?.dragMoved(near: near, screen: screen)
        }
        dragMonitor.onDragEnded = { [weak self] in
            self?.dragEnded()
        }
        dragMonitor.start()

        if let screen = NSScreen.main {
            panel.setFrame(NotchGeometry.windowFrame(on: screen), display: false)
        }
        panel.orderFrontRegardless()
    }

    private func dragMoved(near: Bool, screen: NSScreen?) {
        if near, let screen {
            panel.setFrame(NotchGeometry.windowFrame(on: screen), display: true)
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
            if state.phase == .idle {
                state.phase = .dropTarget(hovering: false)
            }
        } else if case .dropTarget = state.phase {
            collapse()
        }
    }

    private func dragEnded() {
        // Mouse released outside our panel: a drop on the panel itself is
        // delivered via DropView before/independently of this.
        if case .dropTarget = state.phase {
            collapse()
        }
    }

    private func handleDrop(_ urls: [URL]) {
        onFilesDropped?(urls)
        collapse()
    }

    private func collapse() {
        state.phase = .idle
        panel.ignoresMouseEvents = true
    }
}

/// Panel that never steals key/main status from the frontmost app.
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
