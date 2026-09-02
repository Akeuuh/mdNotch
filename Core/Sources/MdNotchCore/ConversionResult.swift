import Foundation

/// Outcome of one source (one dropped file, or one paste).
public struct SourceConversionResult: Sendable {
    public enum Outcome: Sendable {
        /// `outputURL` is nil when no `.md` was written: always the case for
        /// pasted text, which has no folder to write into.
        case success(markdown: String, outputURL: URL?)
        case failure(ConversionError)
    }

    public let source: ConversionSource
    public let outcome: Outcome

    public init(source: ConversionSource, outcome: Outcome) {
        self.source = source
        self.outcome = outcome
    }

    public var isSuccess: Bool {
        if case .success = outcome { return true }
        return false
    }

    /// The markdown came back exactly as it went in — nothing was converted.
    /// Only reachable for pasted plain text, which is already its own
    /// markdown. Worth surfacing: "copied" and "converted" are not the same
    /// claim, and a user who sees the first while expecting the second has no
    /// way to tell them apart.
    public var isUnchanged: Bool {
        guard case .pasted(let pasted) = source,
              case .success(let markdown, _) = outcome
        else { return false }
        return markdown == pasted.text
    }
}

/// Typed conversion failures, one per source. `fileName` names the source as
/// the pipeline saw it (`ConversionSource.displayName`).
public enum ConversionError: Error, Sendable, Equatable {
    /// The file's format is not in the supported list.
    case unsupportedFormat(fileName: String)
    /// The converter failed on the source.
    case conversionFailed(fileName: String, detail: String)
    /// The conversion exceeded the per-source timeout.
    case timedOut(fileName: String)
}

/// Outcome of one run (a drop of one or more files, or one paste).
public struct PipelineResult: Sendable {
    /// One entry per source, in the order they were given.
    public let files: [SourceConversionResult]
    /// Plain-text markdown for the clipboard; nil when nothing succeeded.
    public let clipboardPayload: String?

    public init(files: [SourceConversionResult], clipboardPayload: String?) {
        self.files = files
        self.clipboardPayload = clipboardPayload
    }

    public var failures: [SourceConversionResult] { files.filter { !$0.isSuccess } }
    public var successes: [SourceConversionResult] { files.filter(\.isSuccess) }

    /// Everything that succeeded came back untouched: the run copied text
    /// without converting anything.
    public var changedNothing: Bool {
        !successes.isEmpty && successes.allSatisfy(\.isUnchanged)
    }
}
