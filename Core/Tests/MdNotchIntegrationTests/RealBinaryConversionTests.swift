import XCTest
@testable import MdNotchCore

/// Full-stack conversions through the real frozen markitdown binary.
/// Slow; skipped unless MDNOTCH_INTEGRATION=1. See README.md.
final class RealBinaryConversionTests: XCTestCase {
    private static let marker = "mdNotch integration sample"

    private var outputDir: URL!
    private var pipeline: ConversionPipeline!

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["MDNOTCH_INTEGRATION"] == "1" else {
            throw XCTSkip("integration suite disabled; set MDNOTCH_INTEGRATION=1 to run")
        }
        let binary = try Self.binaryURL()
        outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mdnotch-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        // Production timeout (60 s default) — the suite must pass within it.
        pipeline = ConversionPipeline(converter: SubprocessMarkdownConverter(binaryURL: binary))
    }

    override func tearDownWithError() throws {
        if let outputDir, FileManager.default.fileExists(atPath: outputDir.path) {
            try FileManager.default.removeItem(at: outputDir)
        }
    }

    private static func binaryURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["MDNOTCH_MARKITDOWN_BIN"] {
            return URL(fileURLWithPath: override)
        }
        // <repo>/Core/Tests/MdNotchIntegrationTests/… -> <repo>/scripts/…
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MdNotchIntegrationTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Core
            .deletingLastPathComponent() // repo root
        let url = repoRoot
            .appendingPathComponent("scripts/freeze-markitdown/dist/markitdown-bin/markitdown-bin")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("frozen binary not built; run scripts/freeze-markitdown/build.sh first")
        }
        return url
    }

    private func sample(_ name: String) throws -> URL {
        let url = Bundle.module.resourceURL!
            .appendingPathComponent("Samples")
            .appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("missing sample \(name)")
        }
        return url
    }

    /// Converts one sample and asserts non-empty, plausible markdown.
    private func assertConverts(_ name: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let source = try sample(name)
        let result = await pipeline.process(
            urls: [source],
            settings: PipelineSettings(destination: .fixedFolder(outputDir))
        )
        guard case .success(let markdown, .some(let outputURL)) = result.files[0].outcome else {
            return XCTFail("\(name): expected success, got \(result.files[0].outcome)", file: file, line: line)
        }
        XCTAssertFalse(
            markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "\(name): markdown must be non-empty", file: file, line: line
        )
        XCTAssertTrue(
            markdown.contains(Self.marker),
            "\(name): markdown should contain the sample marker", file: file, line: line
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputURL.path),
            "\(name): .md file must be written", file: file, line: line
        )
    }

    // MARK: - One test per supported format

    func testPDF() async throws { try await assertConverts("sample.pdf") }
    func testDOCX() async throws { try await assertConverts("sample.docx") }
    func testPPTX() async throws { try await assertConverts("sample.pptx") }
    func testXLSX() async throws { try await assertConverts("sample.xlsx") }
    func testXLS() async throws { try await assertConverts("sample.xls") }
    func testHTML() async throws { try await assertConverts("sample.html") }
    func testCSV() async throws { try await assertConverts("sample.csv") }
    func testJSON() async throws { try await assertConverts("sample.json") }
    func testXML() async throws { try await assertConverts("sample.xml") }
    func testEPUB() async throws { try await assertConverts("sample.epub") }

    // MARK: - ZIP: recursive extraction, one concatenated markdown

    func testZIPProducesOneConcatenatedMarkdownCoveringInnerFiles() async throws {
        let source = try sample("sample.zip")
        let result = await pipeline.process(
            urls: [source],
            settings: PipelineSettings(destination: .fixedFolder(outputDir))
        )
        guard case .success(let markdown, _) = result.files[0].outcome else {
            return XCTFail("zip: expected success, got \(result.files[0].outcome)")
        }
        XCTAssertTrue(markdown.contains("ZIP-inner-one"), "zip markdown must cover the first inner file")
        XCTAssertTrue(markdown.contains("ZIP-inner-two"), "zip markdown must cover the second inner file")
        XCTAssertEqual(result.successes.count, 1, "one archive -> one concatenated markdown")
    }

    // MARK: - Rejected format

    func testRejectedFormatFailsWithoutOutput() async throws {
        let source = try sample("sample.png")
        let result = await pipeline.process(
            urls: [source],
            settings: PipelineSettings(destination: .fixedFolder(outputDir))
        )
        guard case .failure(.unsupportedFormat(let fileName)) = result.files[0].outcome else {
            return XCTFail("png: expected unsupportedFormat, got \(result.files[0].outcome)")
        }
        XCTAssertEqual(fileName, "sample.png")
        XCTAssertNil(result.clipboardPayload)
        let contents = try FileManager.default.contentsOfDirectory(atPath: outputDir.path)
        XCTAssertTrue(contents.isEmpty, "no output file may be produced for a rejected format")
    }

    // MARK: - Pasted clipboard HTML

    func testPastedHTMLBecomesMarkdownWithoutTouchingDisk() async throws {
        let html = """
        <h1>\(Self.marker)</h1>
        <p>A <strong>bold</strong> claim and a <a href="https://example.com">link</a>.</p>
        <ul><li>first</li><li>second</li></ul>
        """
        let result = await pipeline.process(
            sources: [.pasted(PastedText(text: html, flavor: .html))],
            settings: PipelineSettings(destination: .fixedFolder(outputDir))
        )

        guard case .success(let markdown, let outputURL) = result.files[0].outcome else {
            return XCTFail("pasted html: expected success, got \(result.files[0].outcome)")
        }
        XCTAssertNil(outputURL)
        XCTAssertTrue(markdown.contains("# \(Self.marker)"), "the heading must survive as a markdown heading")
        XCTAssertTrue(markdown.contains("**bold**"), "inline emphasis must survive")
        XCTAssertTrue(markdown.contains("(https://example.com)"), "links must survive")
        let contents = try FileManager.default.contentsOfDirectory(atPath: outputDir.path)
        XCTAssertTrue(contents.isEmpty, "a paste has no source folder: nothing goes to disk")
    }

    /// The case that looks like a paste failure but isn't one: an `.html` file
    /// copied out of a text editor reaches us as plain text carrying markup.
    func testHTMLSourceCopiedAsPlainTextIsConvertedNotEchoed() async throws {
        let source = """
        <!DOCTYPE html>
        <html lang="en">
        <head><meta charset="utf-8"><title>\(Self.marker)</title></head>
        <body>
          <h1>\(Self.marker)</h1>
          <p>A <strong>bold</strong> claim.</p>
        </body>
        </html>
        """
        let result = await pipeline.process(
            sources: [.pasted(.fromPlainText(source))],
            settings: PipelineSettings()
        )

        guard case .success(let markdown, _) = result.files[0].outcome else {
            return XCTFail("html source: expected success, got \(result.files[0].outcome)")
        }
        XCTAssertFalse(markdown.contains("<h1>"), "no tags may survive in the markdown")
        XCTAssertTrue(markdown.contains("# \(Self.marker)"))
        XCTAssertTrue(markdown.contains("**bold**"))
    }
}
