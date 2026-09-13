import AppKit
import SwiftUI

struct SleepSettingsView: View {
    @Environment(Settings.self) private var settings
    @Environment(AppState.self) private var state
    @Environment(AppController.self) private var controller

    var body: some View {
        @Bindable var settings = settings
        SettingsForm {
            if state.isSleeping {
                SettingsSection {
                    StatusCard(title: QuietStatus.sentence(for: state.sleepReasons),
                               subtitle: "Sounds come back on their own.") {
                        IconTile(symbol: "moon.zzz.fill", size: 32)
                    } accessory: {
                        Button("Wake Now") { controller.wake() }
                    }
                }
            }

            SettingsSection("Go quiet when") {
                Toggle("Microphone is in use", isOn: $settings.sleepOnMicrophone)
                Toggle("Camera is on", isOn: $settings.sleepOnCamera)
                Toggle("Music or Spotify is playing", isOn: $settings.sleepOnNowPlaying)
            }

            MoreOptions {
                SettingsSection("While quiet") {
                    SettingSlider(title: "Volume", subtitle: sleepVolumeDetail, value: $settings.sleepVolume)
                }

                SettingsSection {
                    Toggle("Notify me when Kliq goes quiet or wakes", isOn: Binding(
                        get: { settings.notifyOnSleepChange },
                        set: { on in
                            settings.notifyOnSleepChange = on
                            if on { controller.requestNotificationPermission() }
                        }))
                    if state.notificationsDenied {
                        LabeledContent {
                            Button("Open Notification Settings") { openNotificationSettings() }
                        } label: {
                            Text("\(Image(systemName: "exclamationmark.triangle")) Notifications are off for Kliq")
                            Text("Allow them in System Settings.")
                        }
                    }
                }
            }
        }
    }

    private var sleepVolumeDetail: String {
        settings.sleepVolume <= 0.001 ? "Silent" : "\(Int(settings.sleepVolume * 100))% of normal"
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
