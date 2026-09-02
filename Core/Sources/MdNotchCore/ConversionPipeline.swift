import Foundation

/// Orchestrator: takes sources (dropped files, or pasted text) and settings,
/// returns per-source results plus the clipboard payload. Owns every
/// observable behavior (format gating, naming, concatenation, partial
/// failures, timeout); the UI stays a thin layer above it.
public struct ConversionPipeline: Sendable {
    private let converter: MarkdownConverter
    private let timeout: Duration

    public init(converter: MarkdownConverter, timeout: Duration = .seconds(60)) {
        self.converter = converter
        self.timeout = timeout
    }

    /// Convenience for the dominant case, a drop of files.
    public func process(urls: [URL], settings: PipelineSettings) async -> PipelineResult {
        await process(sources: urls.map(ConversionSource.file), settings: settings)
    }

    public func process(sources: [ConversionSource], settings: PipelineSettings) async -> PipelineResult {
        var files: [SourceConversionResult] = []

        for source in sources {
            files.append(await processOne(source: source, settings: settings))
        }

        return PipelineResult(files: files, clipboardPayload: Self.clipboardPayload(for: files))
    }

    private func processOne(source: ConversionSource, settings: PipelineSettings) async -> SourceConversionResult {
        switch source {
        case .file(let url):
            return await processFile(url: url, settings: settings)
        case .pasted(let pasted):
            return await processPasted(pasted)
        }
    }

    private func processFile(url: URL, settings: PipelineSettings) async -> SourceConversionResult {
        let source = ConversionSource.file(url)
        let fileName = url.lastPathComponent

        guard SupportedFormat.isSupported(url) else {
            return SourceConversionResult(source: source, outcome: .failure(.unsupportedFormat(fileName: fileName)))
        }

        do {
            let markdown = try await convertWithTimeout(url: url, fileName: fileName)
            let outputURL = try write(markdown: markdown, for: url, settings: settings)
            return SourceConversionResult(source: source, outcome: .success(markdown: markdown, outputURL: outputURL))
        } catch let error as ConversionError {
            return SourceConversionResult(source: source, outcome: .failure(error))
        } catch {
            return SourceConversionResult(
                source: source,
                outcome: .failure(.conversionFailed(fileName: fileName, detail: String(describing: error)))
            )
        }
    }

    /// Pasted text has no folder, so nothing is written to disk — the markdown
    /// only reaches the clipboard. Plain text is already markdown and skips
    /// the converter entirely; HTML goes through a scratch file, because the
    /// converter takes URLs.
    private func processPasted(_ pasted: PastedText) async -> SourceConversionResult {
        let source = ConversionSource.pasted(pasted)

        guard pasted.flavor == .html else {
            return SourceConversionResult(source: source, outcome: .success(markdown: pasted.text, outputURL: nil))
        }

        do {
            let scratch = try Self.makeScratchDirectory()
            defer { try? FileManager.default.removeItem(at: scratch) }
            let url = scratch.appendingPathComponent("clipboard.html")
            try pasted.text.write(to: url, atomically: true, encoding: .utf8)
            let markdown = try await convertWithTimeout(url: url, fileName: source.displayName)
            return SourceConversionResult(source: source, outcome: .success(markdown: markdown, outputURL: nil))
        } catch let error as ConversionError {
            return SourceConversionResult(source: source, outcome: .failure(error))
        } catch {
            return SourceConversionResult(
                source: source,
                outcome: .failure(.conversionFailed(fileName: source.displayName, detail: String(describing: error)))
            )
        }
    }

    /// Races the converter against the per-source timeout; the loser is
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

    /// Successful markdowns in source order. A single success goes to the
    /// clipboard as-is; several are concatenated with a `# source-name`
    /// separator before each content.
    private static func clipboardPayload(for files: [SourceConversionResult]) -> String? {
        let successes = files.compactMap { file -> (name: String, markdown: String)? in
            if case .success(let markdown, _) = file.outcome {
                return (file.source.displayName, markdown)
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

    /// Private scratch directory for one paste, deleted as soon as the
    /// converter is done with it.
    private static func makeScratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdnotch-paste-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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
