import Combine
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    /// Connected displays, refreshed when one is plugged or unplugged while
    /// the window is open.
    @State private var screenOptions: [DropZoneScreens] = DropZoneScreens.available

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Save converted files"), selection: $settings.destinationMode) {
                    Text("Next to the source file").tag(AppSettings.DestinationMode.alongsideSource)
                    Text("In a fixed folder").tag(AppSettings.DestinationMode.fixedFolder)
                }
                .pickerStyle(.radioGroup)

                if settings.destinationMode == .fixedFolder {
                    HStack {
                        Text(settings.fixedFolderURL?.path ?? String(localized: "No folder selected"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(String(localized: "Choose…")) {
                            chooseFolder()
                        }
                    }
                }
            }

            Section {
                Picker(String(localized: "Drop zone"), selection: $settings.dropZoneAnchor) {
                    ForEach(DropZoneAnchor.allCases) { anchor in
                        Text(anchor.localizedName).tag(anchor)
                    }
                }
            } footer: {
                Text("Pick a corner if another app already uses the notch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if showsScreenPicker {
                Section {
                    Picker(String(localized: "Active on"), selection: $settings.dropZoneScreens) {
                        ForEach(pickerOptions) { option in
                            Text(option.localizedName).tag(option)
                        }
                    }
                } footer: {
                    Text("Pinning a screen that gets disconnected falls back to the main screen.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Text("Convert clipboard shortcut")
                    Spacer()
                    HotKeyRecorder(combo: $settings.pasteHotKey)
                        .frame(width: 130, height: 24)
                }
            } footer: {
                Text("Click the field and press the keys. ⌫ clears it, ⎋ cancels. The menu bar item converts the clipboard with no shortcut at all.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "Launch at login"), isOn: $settings.launchAtLogin)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenOptions = DropZoneScreens.available
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Nothing to choose from on a single-screen setup — unless the zone is
    /// already restricted, in which case hiding the picker would trap the
    /// user with a setting they cannot undo.
    private var showsScreenPicker: Bool {
        screenOptions.count > 3 || settings.dropZoneScreens != .all
    }

    /// Connected displays, plus the pinned one when it is currently
    /// disconnected — dropping it would silently rewrite the setting to
    /// whatever the picker shows first.
    private var pickerOptions: [DropZoneScreens] {
        let current = settings.dropZoneScreens
        return screenOptions.contains(current) ? screenOptions : screenOptions + [current]
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.fixedFolderURL = url
        }
    }
}
