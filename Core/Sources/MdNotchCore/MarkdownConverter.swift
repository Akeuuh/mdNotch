import Foundation

/// Boundary to the markdown conversion engine. The real implementation runs
/// the frozen markitdown binary in a subprocess; tests substitute a fake.
public protocol MarkdownConverter: Sendable {
    /// Converts the file at `url` to markdown.
    /// Throws on any conversion failure.
    func convertToMarkdown(fileAt url: URL) async throws -> String
}
