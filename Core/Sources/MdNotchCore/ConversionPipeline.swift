import Foundation

/// Orchestrator: takes dropped file URLs and settings, returns per-file
/// results plus the clipboard payload. Owns every observable behavior
/// (format gating, naming, concatenation, partial failures, timeout);
/// the UI stays a thin layer above it.
public struct ConversionPipeline: Sendable {
    private let converter: MarkdownConverter
    private let timeout: Duration

    public init(converter: MarkdownConverter, timeout: Duration = .seconds(60)) {
        self.converter = converter
        self.timeout = timeout
    }

    public func process(urls: [URL], settings: PipelineSettings) async -> PipelineResult {
        var files: [FileConversionResult] = []

        for url in urls {
            files.append(await processOne(url: url, settings: settings))
        }

        return PipelineResult(files: files, clipboardPayload: Self.clipboardPayload(for: files))
    }

    private func processOne(url: URL, settings: PipelineSettings) async -> FileConversionResult {
        let fileName = url.lastPathComponent

        guard SupportedFormat.isSupported(url) else {
            return FileConversionResult(sourceURL: url, outcome: .failure(.unsupportedFormat(fileName: fileName)))
        }

        do {
            let markdown = try await convertWithTimeout(url: url, fileName: fileName)
            let outputURL = try write(markdown: markdown, for: url, settings: settings)
            return FileConversionResult(sourceURL: url, outcome: .success(markdown: markdown, outputURL: outputURL))
        } catch let error as ConversionError {
            return FileConversionResult(sourceURL: url, outcome: .failure(error))
        } catch {
            return FileConversionResult(
                sourceURL: url,
                outcome: .failure(.conversionFailed(fileName: fileName, detail: String(describing: error)))
            )
        }
    }

    /// Races the converter against the per-file timeout; the loser is
    /// cancelled (the subprocess converter kills its child on cancellation).
    private func convertWithTimeout(url: URL, fileName: String) async throws -> String {
        let converter = self.converter
        let timeout = self.timeout
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await converter.convertToMarkdown(fileAt: url)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ConversionError.timedOut(fileName: fileName)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw ConversionError.timedOut(fileName: fileName)
            }
            return first
        }
    }

    /// Successful markdowns in drop order. A single success goes to the
    /// clipboard as-is; several are concatenated with a `# file-name`
    /// separator before each content.
    private static func clipboardPayload(for files: [FileConversionResult]) -> String? {
        let successes = files.compactMap { file -> (name: String, markdown: String)? in
            if case .success(let markdown, _) = file.outcome {
                return (file.sourceURL.lastPathComponent, markdown)
            }
            return nil
        }
        switch successes.count {
        case 0:
            return nil
        case 1:
            return successes[0].markdown
        default:
            return successes
                .map { "# \($0.name)\n\n\($0.markdown)" }
                .joined(separator: "\n\n")
        }
    }

    private func write(markdown: String, for source: URL, settings: PipelineSettings) throws -> URL {
        let directory: URL
        switch settings.destination {
        case .alongsideSource:
            directory = source.deletingLastPathComponent()
        case .fixedFolder(let folder):
            directory = folder
        }
        let baseName = source.deletingPathExtension().lastPathComponent
        let outputURL = Self.availableURL(in: directory, baseName: baseName)
        try markdown.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    /// First free `.md` path: `name.md`, then `name-1.md`, `name-2.md`...
    /// Never overwrites, never asks.
    private static func availableURL(in directory: URL, baseName: String) -> URL {
        let plain = directory.appendingPathComponent(baseName).appendingPathExtension("md")
        if !FileManager.default.fileExists(atPath: plain.path) {
            return plain
        }
        var index = 1
        while true {
            let candidate = directory
                .appendingPathComponent("\(baseName)-\(index)")
                .appendingPathExtension("md")
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
