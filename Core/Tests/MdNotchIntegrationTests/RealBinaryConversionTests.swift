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
        pipeline = ConversionPipeline(
            converter: SubprocessMarkdownConverter(binaryURL: binary),
            timeout: .seconds(120)
        )
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
        guard case .success(let markdown, let outputURL) = result.files[0].outcome else {
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
}
