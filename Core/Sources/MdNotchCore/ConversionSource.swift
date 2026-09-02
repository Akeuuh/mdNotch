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

}
