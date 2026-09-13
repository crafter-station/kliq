import AppKit
import Carbon
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(Settings.self) private var settings
    @Environment(AppState.self) private var state
    @Environment(AppController.self) private var controller

    var body: some View {
        @Bindable var settings = settings
        SettingsForm {
            SettingsSection {
                StatusCard(title: statusTitle, subtitle: statusDetail) {
                    BrandMark(size: 40)
                        .opacity(settings.isEnabled ? 1 : 0.55)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                } accessory: {
                    Toggle("Kliq", isOn: $settings.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                if !state.accessibilityGranted {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Button("Open System Settings") { controller.accessibility.openSystemSettings() }
                            Button("Allow Access") { controller.requestAccessibility() }
                                .buttonStyle(.borderedProminent)
                        }
                    } label: {
                        Text("Allow Accessibility access")
                        Text("Kliq needs it to hear your keys.")
                    }
                    if state.accessibilityStuck {
                        AccessibilityResetRow()
                    }
                }
            }

            SettingsSection {
                ShortcutRow()
                LaunchAtLoginToggle(title: "Launch at login")
            }

            MoreOptions {
                SettingsSection {
                    Toggle(isOn: $settings.dimMenuBarIconWhenOff) {
                        Text("Dim menu bar icon when off")
                        Text("Also while Kliq is quiet.")
                    }
                }

                SettingsSection("Permissions") {
                    LabeledContent("Accessibility") {
                        HStack(spacing: 12) {
                            StatusIndicator(text: state.accessibilityGranted ? "Allowed" : "Not allowed",
                                            isOK: state.accessibilityGranted)
                            Button("Open System Settings") { controller.accessibility.openSystemSettings() }
                        }
                    }
                    LabeledContent("Keyboard") {
                        StatusIndicator(text: state.inputMonitoringActive ? "Listening" : "Not listening",
                                        isOK: state.inputMonitoringActive)
                    }
                    ButtonRow {
                        Button("Show Welcome Guide") { controller.showOnboarding() }
                    }
                } footer: {
                    Text("Kliq only listens for key presses. It never records what you type.")
                }
            }
        }
    }

    private var statusTitle: String {
        if !settings.isEnabled { return "Kliq is off" }
        if state.isSleeping { return QuietStatus.sentence(for: state.sleepReasons) }
        return "Kliq is on"
    }

    private var statusDetail: String? {
        if !settings.isEnabled { return nil }
        if state.isSleeping { return "Sounds come back on their own." }
        guard let set = state.availableSets.first(where: { $0.name == state.currentSetName }) else { return nil }
        return "Playing \(set.displayName)"
    }
}

// MARK: - Shortcut

private struct ShortcutRow: View {
    @Environment(Settings.self) private var settings
    @Environment(AppState.self) private var state
    @Environment(AppController.self) private var controller
    @State private var recorder = ShortcutRecorder()

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if recorder.isRecording {
                    Text("Press keys…")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.3), lineWidth: 1))
                } else if let keycaps = settings.hotKey?.keycaps {
                    KeycapRow(keycaps: keycaps)
                } else {
                    Text("None").foregroundStyle(.secondary)
                }
                Button(recorder.isRecording ? "Cancel" : "Record") {
                    if recorder.isRecording { recorder.stop() } else { record() }
                }
                Button("Clear") { settings.hotKey = nil }
                    .disabled(settings.hotKey == nil || recorder.isRecording)
            }
        } label: {
            Text("Shortcut")
            detail
        }
        .onDisappear { recorder.stop() }
    }

    private var detail: Text {
        if recorder.isRecording {
            return Text(recorder.needsModifier ? "Include ⌃, ⌥ or ⌘." : "Press Esc to cancel.")
        } else if state.hotKeyUnavailable && settings.hotKey != nil {
            return Text("\(Image(systemName: "exclamationmark.triangle")) Another app uses this shortcut")
        }
        return Text("Turns Kliq on or off")
    }

    private func record() {
        controller.setHotKeyRecording(true)
        recorder.start { combo in
            settings.hotKey = combo
        } onFinish: {
            controller.setHotKeyRecording(false)
        }
    }
}

/// Captures the next key press in Kliq's windows as a shortcut. Esc cancels.
@Observable @MainActor
final class ShortcutRecorder {
    private(set) var isRecording = false
    /// The last press had no ⌃, ⌥ or ⌘.
    private(set) var needsModifier = false

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var onFinish: (() -> Void)?

    func start(onCapture: @escaping (HotKeyCombo) -> Void, onFinish: @escaping () -> Void) {
        guard !isRecording else { return }
        isRecording = true
        needsModifier = false
        self.onFinish = onFinish
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if event.keyCode == UInt16(kVK_Escape) && flags.isEmpty {
                self.stop()
            } else if let combo = HotKeyCombo(event: event) {
                onCapture(combo)
                self.stop()
            } else {
                self.needsModifier = true
                NSSound.beep()
            }
            return nil
        }
    }

    /// Ends recording; always hands the shortcut back to the app via `onFinish`.
    func stop() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        needsModifier = false
        onFinish?()
        onFinish = nil
    }
}
