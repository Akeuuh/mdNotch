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
}
