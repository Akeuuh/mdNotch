import AppKit
import Combine
import MdNotchCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var notch: NotchWindowController?
    private var pipeline: ConversionPipeline?
    private var settings: AppSettings?
    private var settingsWindow: SettingsWindowController?
    private var pasteHotKeyRegistration: GlobalHotKey?
    private var cancellables: Set<AnyCancellable> = []
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

        let settings = AppSettings()
        self.settings = settings
        let settingsWindow = SettingsWindowController(settings: settings)
        self.settingsWindow = settingsWindow

        statusBar = StatusBarController(
            settings: settings,
            onSettings: { [weak self] in
                self?.settingsWindow?.show()
            },
            onConvertClipboard: { [weak self] in
                self?.convertClipboard()
            }
        )

        let converterURL = Bundle.main.resourceURL!
            .appendingPathComponent("markitdown-bin")
            .appendingPathComponent("markitdown-bin")
        pipeline = ConversionPipeline(converter: SubprocessMarkdownConverter(binaryURL: converterURL))

        let notch = NotchWindowController(settings: settings)
        notch.onFilesDropped = { [weak self] urls in
            self?.convert(urls.map(ConversionSource.file))
        }
        notch.onTextDropped = { [weak self] pasted in
            self?.convert([.pasted(pasted)])
        }
        notch.onSettingsRequested = { [weak self] in
            self?.settingsWindow?.show()
        }
        notch.start()
        self.notch = notch

        applyPasteHotKey(settings.pasteHotKey)
        settings.$pasteHotKey
            .dropFirst()
            .sink { [weak self] combo in
                MainActor.assumeIsolated {
                    self?.applyPasteHotKey(combo)
                }
            }
            .store(in: &cancellables)
    }

    /// Hotkey and menu bar item both land here: take whatever the clipboard
    /// holds and convert it in place.
    private func convertClipboard() {
        guard let pasted = PasteboardReader.read(from: .general) else {
            // Silence would be indistinguishable from a broken shortcut.
            notch?.showFailure(message: String(localized: "Nothing to convert in the clipboard"))
            return
        }
        convert([.pasted(pasted)])
    }

    private func convert(_ sources: [ConversionSource]) {
        guard let notch, let pipeline, let settings, !isConverting, !sources.isEmpty else { return }
        isConverting = true
        notch.beginConversion()

        let pipelineSettings = settings.pipelineSettings
        Task { @MainActor in
            defer { isConverting = false }
            let result = await pipeline.process(sources: sources, settings: pipelineSettings)

            guard !result.files.isEmpty else {
                notch.collapseNow()
                return
            }

            if let payload = result.clipboardPayload {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(payload, forType: .string)
            }

            if result.failures.isEmpty {
                // "Copied" would claim a conversion that did not happen —
                // the only way for the user to tell the two apart.
                notch.showSuccess(
                    message: result.changedNothing
                        ? String(localized: "Copied as-is")
                        : String(localized: "Copied")
                )
            } else {
                notch.showFailure(message: Self.failureMessage(for: result))
            }
        }
    }

    /// Replaces the registration whenever the user picks another shortcut.
    /// The old one is released by `GlobalHotKey.deinit`, so dropping the
    /// reference is enough.
    private func applyPasteHotKey(_ combo: KeyCombo?) {
        pasteHotKeyRegistration = nil
        guard let combo else { return }
        pasteHotKeyRegistration = GlobalHotKey(combo: combo) { [weak self] in
            self?.convertClipboard()
        }
    }

    /// Short user-facing message covering every failed source of a run.
    static func failureMessage(for result: PipelineResult) -> String {
        result.failures.compactMap { file -> String? in
            guard case .failure(let error) = file.outcome else { return nil }
            if case .pasted = file.source {
                // The clipboard has no file name worth showing.
                switch error {
                case .timedOut:
                    return String(localized: "Clipboard conversion timed out")
                case .unsupportedFormat, .conversionFailed:
                    return String(localized: "Clipboard conversion failed")
                }
            }
            switch error {
            case .unsupportedFormat(let fileName):
                return String(localized: "Unsupported format: \(fileName)")
            case .conversionFailed(let fileName, _):
                return String(localized: "Conversion failed: \(fileName)")
            case .timedOut(let fileName):
                return String(localized: "Conversion timed out: \(fileName)")
            }
        }
        .joined(separator: " · ")
    }
}
