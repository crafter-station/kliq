import SwiftUI

struct SoundSettingsView: View {
    @Environment(Settings.self) private var settings
    @Environment(AppState.self) private var state
    @Environment(AppController.self) private var controller
    @Environment(AudioOutputDevices.self) private var outputDevices

    var body: some View {
        @Bindable var settings = settings
        SettingsForm {
            SettingsSection {
                LabeledContent("Switches") { SoundSetPicker() }
                SettingSlider(title: "Volume", value: $settings.volume)
                LabeledContent("Output") {
                    Picker("Output", selection: $settings.outputDeviceUID) {
                        Text("System output").tag("")
                        if isSavedDeviceMissing {
                            Text("Unavailable device").tag(settings.outputDeviceUID)
                        }
                        if !outputDevices.devices.isEmpty {
                            Divider()
                            ForEach(outputDevices.devices) { device in
                                Text(device.name).tag(device.uid)
                            }
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if let message = state.statusMessage {
                    NoticeRow(text: message)
                }
            }

            MoreOptions {
                SettingsSection("Typing") {
                    Toggle("Vary pitch slightly", isOn: $settings.pitchVariation)
                    Toggle("Stereo by key position", isOn: $settings.stereoPanning)
                    Toggle("Sounds for ⇧ ⌃ ⌥ ⌘", isOn: $settings.audibleModifierKeys)
                    Toggle("Play once when a key is held", isOn: $settings.ignoreKeyRepeat)
                }

                SettingsSection("Effects") {
                    Toggle("Mouse clicks", isOn: $settings.playMouseClicks)
                    Toggle("Ding on Return", isOn: $settings.playDingOnReturn)
                    SettingSlider(title: "Effects volume", value: $settings.effectsVolume)
                }

                SettingsSection("Tone") {
                    SettingSlider(title: "Pitch", value: $settings.tonePitch, range: -1...1,
                                  minimumLabel: "Lower", maximumLabel: "Higher")
                    SettingSlider(title: "Brightness", value: $settings.toneBrightness, range: -1...1,
                                  minimumLabel: "Darker", maximumLabel: "Brighter")
                    ButtonRow {
                        Button("Reset") {
                            settings.tonePitch = 0
                            settings.toneBrightness = 0
                        }
                        .disabled(settings.tonePitch == 0 && settings.toneBrightness == 0)
                        Button("Try It") { controller.previewCurrentSet() }
                    }
                }
            }
        }
    }

    /// A saved device that is unplugged still gets a row, so the picker is never blank.
    private var isSavedDeviceMissing: Bool {
        !settings.outputDeviceUID.isEmpty && !outputDevices.devices.contains { $0.uid == settings.outputDeviceUID }
    }
}
