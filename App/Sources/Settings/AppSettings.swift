import Foundation
import ServiceManagement
import MdNotchCore

/// User settings, persisted in UserDefaults. Launch-at-login state is
/// mirrored into SMAppService.
@MainActor
final class AppSettings: ObservableObject {
    enum DestinationMode: String {
        case alongsideSource
        case fixedFolder
    }

    private enum Keys {
        static let destinationMode = "destinationMode"
        static let fixedFolderPath = "fixedFolderPath"
        static let launchAtLogin = "launchAtLogin"
        static let dropZoneAnchor = "dropZoneAnchor"
    }

    private let defaults: UserDefaults

    @Published var destinationMode: DestinationMode {
        didSet { defaults.set(destinationMode.rawValue, forKey: Keys.destinationMode) }
    }

    @Published var fixedFolderURL: URL? {
        didSet { defaults.set(fixedFolderURL?.path, forKey: Keys.fixedFolderPath) }
    }

    /// Where the drop zone sits. Movable because another notch app can
    /// already own the notch, leaving both zones unusable.
    @Published var dropZoneAnchor: DropZoneAnchor {
        didSet { defaults.set(dropZoneAnchor.rawValue, forKey: Keys.dropZoneAnchor) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            Self.applyLaunchAtLogin(launchAtLogin)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        destinationMode = defaults.string(forKey: Keys.destinationMode)
            .flatMap(DestinationMode.init(rawValue:)) ?? .alongsideSource
        fixedFolderURL = defaults.string(forKey: Keys.fixedFolderPath).map(URL.init(fileURLWithPath:))
        dropZoneAnchor = defaults.string(forKey: Keys.dropZoneAnchor)
            .flatMap(DropZoneAnchor.init(rawValue:)) ?? .notch

        // Enabled by default on first launch.
        if defaults.object(forKey: Keys.launchAtLogin) == nil {
            launchAtLogin = true
            defaults.set(true, forKey: Keys.launchAtLogin)
            Self.applyLaunchAtLogin(true)
        } else {
            launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        }
    }

    /// Settings as the pipeline consumes them.
    var pipelineSettings: PipelineSettings {
        if destinationMode == .fixedFolder, let folder = fixedFolderURL {
            return PipelineSettings(destination: .fixedFolder(folder))
        }
        return PipelineSettings(destination: .alongsideSource)
    }

    private static func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("mdNotch: launch-at-login update failed: %@", String(describing: error))
        }
    }
}
