import AppKit
import MdNotchCore

/// Reads a pasteboard — the general one for a paste, the drag one for a
/// dropped selection — and returns the richest flavor worth converting.
///
/// Order matters: most apps put a plain-text fallback next to their rich
/// flavor, so plain text is only used when nothing better is on offer.
@MainActor
enum PasteboardReader {
    static func read(from pasteboard: NSPasteboard) -> PastedText? {
        if let html = pasteboard.string(forType: .html), !isBlank(html) {
            return PastedText(text: html, flavor: .html)
        }
        // RTF (Pages, TextEdit, Word) carries the same structure as HTML;
        // re-encoding it lets the converter see headings, lists and tables
        // instead of a flat paragraph.
        if let rtf = pasteboard.data(forType: .rtf), let html = htmlString(fromRTF: rtf), !isBlank(html) {
            return PastedText(text: html, flavor: .html)
        }
        if let plain = pasteboard.string(forType: .string), !isBlank(plain) {
            return PastedText(text: plain, flavor: .plain)
        }
        return nil
    }

    private static func htmlString(fromRTF data: Data) -> String? {
        guard let attributed = NSAttributedString(rtf: data, documentAttributes: nil) else { return nil }
        let range = NSRange(location: 0, length: attributed.length)
        guard let htmlData = try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        ) else { return nil }
        return String(data: htmlData, encoding: .utf8)
    }

    /// Whitespace-only content is nothing to convert.
    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
