import Foundation

/// Orchestrator: takes dropped file URLs and settings, returns per-file
/// results plus the clipboard payload. Owns every observable behavior
/// (format gating, naming, concatenation, partial failures, timeout);
/// the UI stays a thin layer above it.
public struct ConversionPipeline: Sendable {
    private let converter: MarkdownConverter

    public init(converter: MarkdownConverter) {
        self.converter = converter
    }

    public func process(urls: [URL], settings: PipelineSettings) async -> PipelineResult {
        var files: [FileConversionResult] = []

        for url in urls {
            files.append(await processOne(url: url, settings: settings))
        }

        let successes = files.compactMap { file -> String? in
            if case .success(let markdown, _) = file.outcome { return markdown }
            return nil
        }
        let payload = successes.isEmpty ? nil : successes.joined()

        return PipelineResult(files: files, clipboardPayload: payload)
    }

    private func processOne(url: URL, settings: PipelineSettings) async -> FileConversionResult {
        do {
            let markdown = try await converter.convertToMarkdown(fileAt: url)
            let outputURL = try write(markdown: markdown, for: url, settings: settings)
            return FileConversionResult(sourceURL: url, outcome: .success(markdown: markdown, outputURL: outputURL))
        } catch {
            let fileName = url.lastPathComponent
            return FileConversionResult(
                sourceURL: url,
                outcome: .failure(.conversionFailed(fileName: fileName, detail: String(describing: error)))
            )
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
        let outputURL = directory.appendingPathComponent(baseName).appendingPathExtension("md")
        try markdown.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }
}
