import AppKit
import Combine
import MdNotchCore
import SwiftUI

/// Borderless always-on-top panel anchored under the notch (or in a screen
/// corner, per `AppSettings.dropZoneAnchor`). Invisible at rest; extends when
/// a convertible drag comes near; accepts drops and hands files to
/// `onFilesDropped`, dragged selections to `onTextDropped`.
@MainActor
final class NotchWindowController {
    let state = NotchState()
    var onFilesDropped: (([URL]) -> Void)?
    var onTextDropped: ((PastedText) -> Void)?
    var onSettingsRequested: (() -> Void)?

    private let settings: AppSettings
    private let panel: NSPanel
    private let dragMonitor = DragMonitor()
    private let hoverMonitor = HoverMonitor()
    private var collapseTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    private var anchor: DropZoneAnchor { settings.dropZoneAnchor }

    init(settings: AppSettings) {
        self.settings = settings
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
            guard let self, self.state.phase == .idle || self.isDropTarget else { return }
            self.state.phase = .dropTarget(hovering: true)
        }
        dropView.onDragExited = { [weak self] in
            guard let self, self.isDropTarget else { return }
            self.state.phase = .dropTarget(hovering: false)
        }
        dropView.onFilesDropped = { [weak self] urls in
            self?.onFilesDropped?(urls)
        }
        dropView.onTextDropped = { [weak self] pasted in
            self?.onTextDropped?(pasted)
        }
        dropView.canAcceptDrop = { [weak self] in
            guard let self else { return false }
            return self.state.phase == .idle || self.isDropTarget || self.state.phase == .settingsHover
        }
        dropView.onClicked = { [weak self] in
            guard let self else { return }
            switch self.state.phase {
            case .failure:
                // Error feedback collapses on click.
                self.collapse()
            case .settingsHover:
                self.collapse()
                self.onSettingsRequested?()
            default:
                break
            }
        }

        let hosting = NSHostingView(rootView: NotchView(state: state))
        hosting.autoresizingMask = [.width, .height]
        dropView.addSubview(hosting)
        panel.contentView = dropView
        hosting.frame = dropView.bounds

        state.anchor = settings.dropZoneAnchor
    }

    func start() {
        dragMonitor.anchor = anchor
        dragMonitor.onUpdate = { [weak self] near, screen in
            self?.dragMoved(near: near, screen: screen)
        }
        dragMonitor.onDragEnded = { [weak self] in
            self?.dragEnded()
        }
        dragMonitor.start()

        // Moving the zone while it is out would leave the panel behind.
        settings.$dropZoneAnchor
            .dropFirst()
            .sink { [weak self] anchor in
                MainActor.assumeIsolated {
                    self?.anchorChanged(to: anchor)
                }
            }
            .store(in: &cancellables)

        hoverMonitor.onMouseMoved = { [weak self] location, screen in
            self?.mouseMoved(to: location, screen: screen)
        }
        hoverMonitor.start()

        if let screen = NSScreen.main {
            panel.setFrame(NotchGeometry.windowFrame(for: anchor, on: screen), display: false)
        }
        panel.orderFrontRegardless()
    }

    /// Call when a conversion starts: spinner + glow.
    func beginConversion() {
        collapseTask?.cancel()
        placeIfHidden()
        state.phase = .converting
        // Nothing to click while it runs, and the window is wide enough to
        // cover part of the menu bar — let events through.
        panel.ignoresMouseEvents = true
    }

    /// Call when the pipeline finished. Success: green check + `message`,
    /// auto-collapse after ~2 s.
    func showSuccess(message: String) {
        state.phase = .success(message: message)
        scheduleCollapse(after: 2)
    }

    /// Call when at least one file failed: red cross + message,
    /// collapse on click or after ~4 s.
    func showFailure(message: String) {
        collapseTask?.cancel()
        placeIfHidden()
        state.phase = .failure(message: message)
        // Dismissable by clicking it.
        panel.ignoresMouseEvents = false
        scheduleCollapse(after: 4)
    }

    func collapseNow() {
        collapse()
    }

    private func mouseMoved(to location: NSPoint, screen: NSScreen?) {
        guard let screen else {
            if state.phase == .settingsHover { collapse() }
            return
        }

        switch state.phase {
        case .idle:
            guard NSMouseInRect(location, NotchGeometry.hoverRegion(for: anchor, on: screen), false) else { return }
            // The pill hangs clear of the notch (or of the menu bar): anything
            // drawn inside the notch itself would be invisible.
            state.anchor = anchor
            state.topInset = 0
            reveal(NotchGeometry.gearFrame(for: anchor, on: screen))
            state.phase = .settingsHover
        case .settingsHover:
            // Wider region while out, so the pointer can travel onto the
            // pill and click it.
            if !NSMouseInRect(location, NotchGeometry.gearKeepRegion(for: anchor, on: screen), false) {
                collapse()
            }
        default:
            break
        }
    }

    private func dragMoved(near: Bool, screen: NSScreen?) {
        if near, let screen {
            // Never interrupt an ongoing conversion or its feedback.
            guard state.phase == .idle || isDropTarget || state.phase == .settingsHover else { return }
            state.anchor = anchor
            state.topInset = NotchGeometry.contentTopInset(for: anchor, on: screen)
            reveal(NotchGeometry.windowFrame(for: anchor, on: screen))
            if state.phase == .idle || state.phase == .settingsHover {
                state.phase = .dropTarget(hovering: false)
            }
        } else if isDropTarget {
            collapse()
        }
    }

    /// The zone moved: pull it back in and park the panel on the new anchor,
    /// so the next reveal doesn't animate in from the old position.
    private func anchorChanged(to anchor: DropZoneAnchor) {
        dragMonitor.anchor = anchor
        collapse()
        state.anchor = anchor
        if let screen = NSScreen.main {
            panel.setFrame(NotchGeometry.windowFrame(for: anchor, on: screen), display: false)
        }
    }

    /// Brings the zone out on the active screen when nothing is showing yet.
    /// A paste has no drag to reveal it, and the settings pill sits at a
    /// different frame; a conversion already on screen is left alone, so its
    /// feedback never jumps to another display.
    private func placeIfHidden() {
        switch state.phase {
        case .idle, .settingsHover:
            guard let screen = Self.activeScreen else { return }
            state.anchor = anchor
            state.topInset = NotchGeometry.contentTopInset(for: anchor, on: screen)
            reveal(NotchGeometry.windowFrame(for: anchor, on: screen))
        default:
            return
        }
    }

    /// Positions the panel and makes it interactive.
    private func reveal(_ frame: NSRect) {
        panel.setFrame(frame, display: true)
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
    }

    private func dragEnded() {
        // Mouse released outside our panel: a drop on the panel itself is
        // delivered via DropView before/independently of this.
        if isDropTarget {
            collapse()
        }
    }

    private var isDropTarget: Bool {
        if case .dropTarget = state.phase { return true }
        return false
    }

    /// Screen the user is currently working on: the one under the pointer,
    /// falling back to the main one.
    private static var activeScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func scheduleCollapse(after seconds: Double) {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.collapse()
        }
    }

    private func collapse() {
        collapseTask?.cancel()
        state.phase = .idle
        panel.ignoresMouseEvents = true
    }
}

/// Panel that never steals key/main status from the frontmost app.
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
