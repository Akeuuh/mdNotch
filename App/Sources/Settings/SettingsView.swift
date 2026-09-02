import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

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
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
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
