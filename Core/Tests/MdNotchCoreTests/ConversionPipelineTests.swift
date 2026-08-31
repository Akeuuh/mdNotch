import XCTest
@testable import MdNotchCore

/// Fake converter: pure in-memory, no binary involved. Records invocations.
final class FakeConverter: MarkdownConverter, @unchecked Sendable {
    private let handler: @Sendable (URL) async throws -> String
    private let lock = NSLock()
    private var _invocations: [URL] = []

    var invocations: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _invocations
    }

    init(_ handler: @escaping @Sendable (URL) async throws -> String) {
        self.handler = handler
    }

    /// Convenience: returns fixed markdown for every file.
    convenience init(markdown: String) {
        self.init { _ in markdown }
    }

    func convertToMarkdown(fileAt url: URL) async throws -> String {
        lock.lock()
        _invocations.append(url)
        lock.unlock()
        return try await handler(url)
    }
}

struct FakeFailure: Error {}

final class ConversionPipelineTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdnotch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
    }

    /// Creates a source file in the temp dir and returns its URL.
    private func makeSourceFile(named name: String, contents: String = "dummy") throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Tracer bullet: single file happy path

    func testSingleFileSuccessReturnsMarkdownAndClipboardPayload() async throws {
        let source = try makeSourceFile(named: "report.pdf")
        let pipeline = ConversionPipeline(converter: FakeConverter(markdown: "# Hello"))

        let result = await pipeline.process(urls: [source], settings: PipelineSettings())

        XCTAssertEqual(result.files.count, 1)
        guard case .success(let markdown, _) = result.files[0].outcome else {
            return XCTFail("expected success, got \(result.files[0].outcome)")
        }
        XCTAssertEqual(markdown, "# Hello")
        XCTAssertEqual(result.clipboardPayload, "# Hello")
    }

    func testSingleFileWritesMarkdownAlongsideSourceNamedAfterIt() async throws {
        let source = try makeSourceFile(named: "report.pdf")
        let pipeline = ConversionPipeline(converter: FakeConverter(markdown: "# Hello"))

        let result = await pipeline.process(urls: [source], settings: PipelineSettings())

        let expected = tempDir.appendingPathComponent("report.md")
        guard case .success(_, let outputURL) = result.files[0].outcome else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(outputURL.standardizedFileURL, expected.standardizedFileURL)
        XCTAssertEqual(try String(contentsOf: expected, encoding: .utf8), "# Hello")
    }

    // MARK: - Format gating

    func testUnsupportedFormatIsRejectedWithoutInvokingConverter() async throws {
        let converter = FakeConverter(markdown: "# nope")
        let pipeline = ConversionPipeline(converter: converter)

        for name in ["photo.png", "song.mp3", "movie.mov", "notes.txt", "archive.rar"] {
            let source = try makeSourceFile(named: name)
            let result = await pipeline.process(urls: [source], settings: PipelineSettings())

            guard case .failure(let error) = result.files[0].outcome else {
                return XCTFail("\(name): expected failure")
            }
            XCTAssertEqual(error, .unsupportedFormat(fileName: name))
            XCTAssertNil(result.clipboardPayload)
        }
        XCTAssertTrue(converter.invocations.isEmpty, "converter must never be invoked for rejected formats")
    }

    func testAllElevenSupportedFormatsPassGating() async throws {
        let extensions = ["pdf", "docx", "pptx", "xlsx", "xls", "html", "csv", "json", "xml", "epub", "zip"]
        let pipeline = ConversionPipeline(converter: FakeConverter(markdown: "# ok"))

        for ext in extensions {
            let source = try makeSourceFile(named: "file-\(ext).\(ext.uppercased())") // case-insensitive too
            let result = await pipeline.process(urls: [source], settings: PipelineSettings())
            XCTAssertTrue(result.files[0].isSuccess, "\(ext) should be supported")
        }
    }

    // MARK: - Conversion failures

    func testConverterFailureYieldsTypedErrorNamingTheFile() async throws {
        let source = try makeSourceFile(named: "rapport.pdf")
        let pipeline = ConversionPipeline(converter: FakeConverter { _ in throw FakeFailure() })

        let result = await pipeline.process(urls: [source], settings: PipelineSettings())

        guard case .failure(.conversionFailed(let fileName, _)) = result.files[0].outcome else {
            return XCTFail("expected conversionFailed, got \(result.files[0].outcome)")
        }
        XCTAssertEqual(fileName, "rapport.pdf")
        XCTAssertNil(result.clipboardPayload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("rapport.md").path))
    }

    // MARK: - Timeout

    func testConversionExceedingTimeoutIsInterrupted() async throws {
        let source = try makeSourceFile(named: "slow.pdf")
        let slowConverter = FakeConverter { _ in
            try await Task.sleep(for: .seconds(5))
            return "# too late"
        }
        let pipeline = ConversionPipeline(converter: slowConverter, timeout: .milliseconds(50))

        let start = ContinuousClock.now
        let result = await pipeline.process(urls: [source], settings: PipelineSettings())
        let elapsed = ContinuousClock.now - start

        XCTAssertLessThan(elapsed, .seconds(2), "timeout must interrupt, not wait for the converter")
        guard case .failure(.timedOut(let fileName)) = result.files[0].outcome else {
            return XCTFail("expected timedOut, got \(result.files[0].outcome)")
        }
        XCTAssertEqual(fileName, "slow.pdf")
    }

    // MARK: - Multi-drop

    func testMultiDropWritesOneFilePerSourceAndConcatenatesClipboard() async throws {
        let a = try makeSourceFile(named: "alpha.pdf")
        let b = try makeSourceFile(named: "beta.docx")
        let pipeline = ConversionPipeline(converter: FakeConverter { url in
            "content of \(url.lastPathComponent)"
        })

        let result = await pipeline.process(urls: [a, b], settings: PipelineSettings())

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("alpha.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("beta.md").path))
        XCTAssertEqual(
            result.clipboardPayload,
            "# alpha.pdf\n\ncontent of alpha.pdf\n\n# beta.docx\n\ncontent of beta.docx"
        )
    }

    func testClipboardOrderMatchesDropOrder() async throws {
        let names = ["c.pdf", "a.pdf", "b.pdf"]
        var urls: [URL] = []
        for name in names {
            urls.append(try makeSourceFile(named: name))
        }
        let pipeline = ConversionPipeline(converter: FakeConverter { "md:\($0.lastPathComponent)" })

        let result = await pipeline.process(urls: urls, settings: PipelineSettings())

        XCTAssertEqual(
            result.clipboardPayload,
            "# c.pdf\n\nmd:c.pdf\n\n# a.pdf\n\nmd:a.pdf\n\n# b.pdf\n\nmd:b.pdf"
        )
    }

    func testNameConflictGetsAutoSuffixWithoutOverwriting() async throws {
        let source = try makeSourceFile(named: "rapport.pdf")
        let existing = tempDir.appendingPathComponent("rapport.md")
        try "existing".write(to: existing, atomically: true, encoding: .utf8)
        let pipeline = ConversionPipeline(converter: FakeConverter(markdown: "# new"))

        let first = await pipeline.process(urls: [source], settings: PipelineSettings())
        let second = await pipeline.process(urls: [source], settings: PipelineSettings())

        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "existing", "must never overwrite")
        guard case .success(_, let firstURL) = first.files[0].outcome,
              case .success(_, let secondURL) = second.files[0].outcome else {
            return XCTFail("expected successes")
        }
        XCTAssertEqual(firstURL.lastPathComponent, "rapport-1.md")
        XCTAssertEqual(secondURL.lastPathComponent, "rapport-2.md")
        XCTAssertEqual(try String(contentsOf: firstURL, encoding: .utf8), "# new")
        XCTAssertEqual(try String(contentsOf: secondURL, encoding: .utf8), "# new")
    }

    func testMixedBatchConvertsSuccessesAndReportsFailures() async throws {
        let good = try makeSourceFile(named: "good.pdf")
        let unsupported = try makeSourceFile(named: "photo.png")
        let bad = try makeSourceFile(named: "corrupt.docx")
        let pipeline = ConversionPipeline(converter: FakeConverter { url in
            if url.lastPathComponent == "corrupt.docx" { throw FakeFailure() }
            return "# good content"
        })

        let result = await pipeline.process(urls: [good, unsupported, bad], settings: PipelineSettings())

        XCTAssertEqual(result.successes.map(\.sourceURL.lastPathComponent), ["good.pdf"])
        XCTAssertEqual(
            result.failures.map(\.sourceURL.lastPathComponent).sorted(),
            ["corrupt.docx", "photo.png"]
        )
        // Successes still reach the clipboard and disk.
        XCTAssertEqual(result.clipboardPayload, "# good content")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("good.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("corrupt.md").path))
    }

    func testFixedFolderDestinationReceivesAllOutputs() async throws {
        let dest = tempDir.appendingPathComponent("outbox")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let a = try makeSourceFile(named: "one.pdf")
        let b = try makeSourceFile(named: "two.pdf")
        let pipeline = ConversionPipeline(converter: FakeConverter(markdown: "# md"))

        let result = await pipeline.process(
            urls: [a, b],
            settings: PipelineSettings(destination: .fixedFolder(dest))
        )

        XCTAssertEqual(result.successes.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("one.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("two.md").path))
    }
}
