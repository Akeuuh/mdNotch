import AppKit
import MdNotchCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var notch: NotchWindowController?
    private var pipeline: ConversionPipeline?
    private var isConverting = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement in Info.plist already hides the Dock icon; this keeps
        // behavior correct when launched from Xcode or a debug build.
        NSApp.setActivationPolicy(.accessory)

        statusBar = StatusBarController()

        let converterURL = Bundle.main.resourceURL!
            .appendingPathComponent("markitdown-bin")
            .appendingPathComponent("markitdown-bin")
        pipeline = ConversionPipeline(converter: SubprocessMarkdownConverter(binaryURL: converterURL))

        let notch = NotchWindowController()
        notch.onFilesDropped = { [weak self] urls in
            self?.handleDrop(urls)
        }
        notch.start()
        self.notch = notch
    }

    private func handleDrop(_ urls: [URL]) {
        guard let notch, let pipeline, !isConverting else { return }
        isConverting = true
        notch.beginConversion()

        Task { @MainActor in
            defer { isConverting = false }
            let result = await pipeline.process(urls: urls, settings: PipelineSettings())

            if let payload = result.clipboardPayload {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(payload, forType: .string)
            }

            if result.failures.isEmpty && !result.files.isEmpty {
                notch.showSuccess()
            } else {
                // Minimal handling for now; full error UI comes with the
                // format-gating milestone.
                notch.collapseNow()
            }
        }
    }
}
