import XCTest
@testable import MdNotchCore

/// Fake converter: pure in-memory, no binary involved.
final class FakeConverter: MarkdownConverter, @unchecked Sendable {
    private let handler: @Sendable (URL) async throws -> String

    init(_ handler: @escaping @Sendable (URL) async throws -> String) {
        self.handler = handler
    }

    /// Convenience: returns fixed markdown for every file.
    convenience init(markdown: String) {
        self.init { _ in markdown }
    }

    func convertToMarkdown(fileAt url: URL) async throws -> String {
        try await handler(url)
    }
}

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
}
