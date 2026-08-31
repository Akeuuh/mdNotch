import AppKit

/// Content view of the notch panel: receives file drops and forwards them.
final class DropView: NSView {
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    var onFilesDropped: (([URL]) -> Void)?
    var onClicked: (() -> Void)?
    /// When false, drags are refused (no-drop cursor) instead of silently
    /// swallowed — e.g. while a conversion is already running.
    var canAcceptDrop: (() -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptDrop?() ?? true else { return [] }
        onDragEntered?()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard canAcceptDrop?() ?? true else { return false }
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onFilesDropped?(urls)
        return true
    }
}
