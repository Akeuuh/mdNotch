import AppKit
import MdNotchCore

/// Content view of the notch panel: receives file drops and dragged text
/// selections, and forwards them.
final class DropView: NSView {
    var onDragEntered: (() -> Void)?
    var onDragExited: (() -> Void)?
    var onFilesDropped: (([URL]) -> Void)?
    var onTextDropped: ((PastedText) -> Void)?
    var onClicked: (() -> Void)?
    /// When false, drags are refused (no-drop cursor) instead of silently
    /// swallowed — e.g. while a conversion is already running.
    var canAcceptDrop: (() -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Plain strings are deliberately left out: they need no conversion,
        // and accepting them would make the zone a target for every
        // in-editor text move. See DragMonitor.
        registerForDraggedTypes([.fileURL, .html, .rtf])
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

        // Files win over text: a dragged file also advertises its name as a
        // string on the same pasteboard.
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        if !urls.isEmpty {
            onFilesDropped?(urls)
            return true
        }

        guard let pasted = PasteboardReader.read(from: sender.draggingPasteboard) else { return false }
        onTextDropped?(pasted)
        return true
    }
}
