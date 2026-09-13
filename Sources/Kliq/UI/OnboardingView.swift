import AppKit
import SwiftUI

/// First-run guide: grant Accessibility, pick a switch set, optionally launch at login.
struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @Environment(AppController.self) private var controller

    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Sits in the titlebar band, centered clear of the traffic lights.
            VStack(spacing: 4) {
                BrandMark(size: 60)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .padding(.bottom, 10)
                Text("Welcome to Kliq").font(.title2.weight(.semibold))
                Text("Mechanical keyboard sounds for every keystroke.").foregroundStyle(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 12)

            SettingsForm {
                step(number: 1, title: "Let Kliq hear your keys") {
                    Text("Kliq needs Accessibility access to notice key presses. It never records what you type.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        StatusIndicator(text: state.accessibilityGranted ? "Allowed" : "Waiting for permission",
                                        isOK: state.accessibilityGranted)
                        Spacer()
                        if !state.accessibilityGranted {
                            Button("Open System Settings") { controller.accessibility.openSystemSettings() }
                            Button("Allow Access") { controller.requestAccessibility() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    if state.accessibilityStuck && !state.accessibilityGranted {
                        AccessibilityResetRow()
                    }
                }

                step(number: 2, title: "Pick your switches") {
                    LabeledContent("Switches") { SoundSetPicker() }
                } footer: {
                    Text("Change them any time from the menu bar.")
                }

                step(number: 3, title: "Start automatically") {
                    LaunchAtLoginToggle(title: "Launch Kliq at login")
                }
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .tint(Brand.accent)
                    .disabled(!state.accessibilityGranted)
            }
            .padding(.horizontal, SettingsMetrics.pageInset)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 600)
        .background(WindowBackdrop())
    }

    private func step<Content: View, Footer: View>(number: Int, title: String, @ViewBuilder content: () -> Content,
                                                 @ViewBuilder footer: () -> Footer) -> some View {
        SettingsSection(content: content) {
            HStack(spacing: 8) {
                Keycap(label: "\(number)", height: 20)
                Text(title)
            }
        } footer: {
            footer()
        }
    }

    private func step<Content: View>(number: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
        step(number: number, title: title, content: content) { EmptyView() }
    }
}

/// Shown when Allow Access doesn't lead to permission. macOS then holds an entry for an
/// earlier build of Kliq that it won't apply and won't ask about again; resetting it
/// brings the system prompt back.
struct AccessibilityResetRow: View {
    @Environment(AppController.self) private var controller

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Still waiting? If Kliq already shows as on in System Settings, macOS is holding an older permission. Reset it, then allow Kliq when macOS asks.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Reset and Allow") { controller.resetAccessibility() }
        }
    }
}
