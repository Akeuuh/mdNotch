import Foundation

/// What one conversion was asked to turn into markdown: a file on disk, or
/// text taken from the clipboard (pasted, or dragged as a selection).
///
/// The two differ in more than their input. A file has a folder, so its
/// markdown is written next to it (or into the fixed folder); pasted text has
/// no origin on disk, so it never produces a `.md` — its markdown only
/// reaches the clipboard.
public enum ConversionSource: Sendable, Equatable {
    case file(URL)
    case pasted(PastedText)

    /// Name used to identify the source in failures, and as the heading of a
    /// multi-source clipboard payload.
    public var displayName: String {
        switch self {
        case .file(let url):
            return url.lastPathComponent
        case .pasted:
            return "clipboard"
        }
    }
}

/// Text handed over without a file behind it, in the richest flavor the
/// clipboard offered.
public struct PastedText: Sendable, Equatable {
    /// How `text` is encoded, which decides how it reaches markdown.
    public enum Flavor: String, Sendable, Equatable {
        /// An HTML document or fragment — a copy out of a browser, a word
        /// processor, a notes app. Goes through the converter.
        case html
        /// Plain text: already its own markdown. Never touches the converter.
        case plain
    }

    public let text: String
    public let flavor: Flavor

    public init(text: String, flavor: Flavor) {
        self.text = text
        self.flavor = flavor
    }

    /// Classifies text that arrived with no rich flavor at all.
    ///
    /// Copying an `.html` file out of a text editor yields *plain text that is
    /// a document*: no `public.html` on the pasteboard, markup in the string.
    /// Treating that as plain text copies it back untouched, which is not what
    /// anyone means by it.
    ///
    /// Only a document-level signal counts. A stray `<b>` in prose, or an HTML
    /// example inside a fenced markdown block, must stay plain — being wrong
    /// here mangles text that was already correct.
    public static func fromPlainText(_ text: String) -> PastedText {
        PastedText(text: text, flavor: looksLikeHTMLDocument(text) ? .html : .plain)
    }

    private static func looksLikeHTMLDocument(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Markup, if any, has to start the text: prose that merely mentions a
        // tag is prose.
        guard trimmed.hasPrefix("<") else { return false }

        let head = trimmed.prefix(2048).lowercased()
        if head.hasPrefix("<!doctype html") || head.hasPrefix("<html") { return true }
        // A leading comment or XML declaration can push the opening tag down,
        // so fall back to the document's own closing tag. Bounded window: a
        // long paste should not be lowercased in full.
        let tail = trimmed.suffix(2048).lowercased()
        return tail.contains("</html>") || tail.contains("</body>")
    }
}
