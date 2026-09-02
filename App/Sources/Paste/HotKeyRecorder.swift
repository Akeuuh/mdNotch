import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click-to-record shortcut field, the way system preferences do it.
///
/// While armed it swallows key equivalents too, so a combination that already
/// means something in this app can still be recorded — the point is to pick
/// one that is free *elsewhere*, and only the user knows that.
struct HotKeyRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo?

    func makeNSView(context: Context) -> HotKeyRecorderView {
        let view = HotKeyRecorderView()
        let binding = $combo
        view.combo = combo
        view.onRecord = { binding.wrappedValue = $0 }
        return view
    }

    func updateNSView(_ view: HotKeyRecorderView, context: Context) {
        view.combo = combo
    }
}

final class HotKeyRecorderView: NSView {
    /// nil once the user clears the shortcut with ⌫.
    var onRecord: ((KeyCombo?) -> Void)?

    var combo: KeyCombo? {
        didSet { needsDisplay = true }
    }

    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    /// Modifiers held down mid-recording, echoed back so the field reacts
    /// before the user commits to a key.
    private var pendingModifiers: NSEvent.ModifierFlags = [] {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 24) }
    override var isFlipped: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        pendingModifiers = []
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        pendingModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = UInt32(event.keyCode)

        // Bare ⎋ backs out, bare ⌫ clears — the two conventions every
        // shortcut field on macOS follows.
        if modifiers.isEmpty, keyCode == UInt32(kVK_Escape) {
            stopRecording()
            return
        }
        if modifiers.isEmpty, keyCode == UInt32(kVK_Delete) {
            combo = nil
            onRecord?(nil)
            stopRecording()
            return
        }

        let candidate = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        guard candidate.isValid else {
            // A shortcut without ⌘, ⌃ or ⌥ would swallow ordinary typing
            // everywhere.
            NSSound.beep()
            return
        }
        combo = candidate
        onRecord?(candidate)
        stopRecording()
    }

    /// Menu shortcuts are matched before `keyDown`; while recording, we want
    /// them as input rather than as commands.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        keyDown(with: event)
        return true
    }

    private func stopRecording() {
        isRecording = false
        pendingModifiers = []
    }

    private var title: String {
        if isRecording {
            let held = KeyCombo.symbols(for: pendingModifiers)
            return held.isEmpty ? String(localized: "Type a shortcut") : held
        }
        return combo?.displayString ?? String(localized: "Not set")
    }

    override func draw(_ dirtyRect: NSRect) {
        let border = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: border, xRadius: 6, yRadius: 6)

        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
        } else {
            NSColor.controlBackgroundColor.setFill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
        }
        path.fill()
        path.stroke()

        let text = title as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: isRecording || combo != nil
                ? NSColor.labelColor
                : NSColor.secondaryLabelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }
}
