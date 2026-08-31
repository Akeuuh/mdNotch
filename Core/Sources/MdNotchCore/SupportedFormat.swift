import Foundation

/// The 11 formats markitdown converts offline. Everything else is rejected
/// before the converter is ever invoked.
public enum SupportedFormat: String, CaseIterable, Sendable {
    case pdf, docx, pptx, xlsx, xls, html, csv, json, xml, epub, zip

    public static func isSupported(_ url: URL) -> Bool {
        SupportedFormat(rawValue: url.pathExtension.lowercased()) != nil
    }
}
