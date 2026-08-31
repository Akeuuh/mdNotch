import Foundation

/// Real `MarkdownConverter`: invokes the frozen markitdown binary as a
/// subprocess. Markdown is read from stdout; a non-zero exit means failure
/// and stderr carries the message.
public struct SubprocessMarkdownConverter: MarkdownConverter {
    public enum SubprocessError: Error, Sendable {
        case launchFailed(underlying: String)
        case exited(status: Int32, stderr: String)
    }

    private let binaryURL: URL

    public init(binaryURL: URL) {
        self.binaryURL = binaryURL
    }

    public func convertToMarkdown(fileAt url: URL) async throws -> String {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = [url.path]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw SubprocessError.launchFailed(underlying: String(describing: error))
        }

        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { () throws -> String in
                // Drain stderr on a separate queue so neither pipe can fill
                // up and deadlock the child.
                nonisolated(unsafe) var errData = Data()
                let drained = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .utility).async {
                    errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    drained.signal()
                }
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                drained.wait()
                process.waitUntilExit()

                try Task.checkCancellation()

                guard process.terminationStatus == 0 else {
                    throw SubprocessError.exited(
                        status: process.terminationStatus,
                        stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                return String(decoding: outData, as: UTF8.self)
            }.value
        } onCancel: {
            // Kill the child on timeout/cancellation; the pipes hit EOF and
            // the reader task unblocks.
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }
}
