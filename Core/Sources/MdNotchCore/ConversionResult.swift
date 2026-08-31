import Foundation

/// Outcome of one dropped file.
public struct FileConversionResult: Sendable {
    public enum Outcome: Sendable {
        case success(markdown: String, outputURL: URL)
        case failure(ConversionError)
    }

    public let sourceURL: URL
    public let outcome: Outcome

    public init(sourceURL: URL, outcome: Outcome) {
        self.sourceURL = sourceURL
        self.outcome = outcome
    }

    public var isSuccess: Bool {
        if case .success = outcome { return true }
        return false
    }
}

/// Typed conversion failures, one per file.
public enum ConversionError: Error, Sendable, Equatable {
    /// The file's format is not in the supported list.
    case unsupportedFormat(fileName: String)
    /// The converter failed on the file.
    case conversionFailed(fileName: String, detail: String)
    /// The conversion exceeded the per-file timeout.
    case timedOut(fileName: String)
}

/// Outcome of one drop (one or more files).
public struct PipelineResult: Sendable {
    /// One entry per dropped file, in drop order.
    public let files: [FileConversionResult]
    /// Plain-text markdown for the clipboard; nil when nothing succeeded.
    public let clipboardPayload: String?

    public init(files: [FileConversionResult], clipboardPayload: String?) {
        self.files = files
        self.clipboardPayload = clipboardPayload
    }

    public var failures: [FileConversionResult] { files.filter { !$0.isSuccess } }
    public var successes: [FileConversionResult] { files.filter(\.isSuccess) }
}
