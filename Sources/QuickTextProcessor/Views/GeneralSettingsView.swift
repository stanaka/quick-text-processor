import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var settings: SettingsStore

    /// Bumped to re-evaluate the Accessibility status after the user visits
    /// System Settings.
    @State private var permissionCheck = 0

    var body: some View {
        Form {
            Section("Global shortcut") {
                HotkeyRecorderView()
                Text("Press the shortcut in any app to capture the selection and open the task palette. Press it again to dismiss.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Accessibility permission") {
                HStack(spacing: 8) {
                    let granted = accessibilityGranted
                    Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(granted ? Color.green : Color.orange)
                    Text(granted
                         ? "Granted — selection capture and insert-back are available."
                         : "Not granted — only the clipboard fallback will work.")
                    Spacer()
                    Button("Recheck") { permissionCheck += 1 }
                    Button("Open System Settings") {
                        controller.requestAccessibility()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                Text("Rebuilding with an ad-hoc signature makes macOS forget this grant — run `make cert` once (see README) so rebuilds keep it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Context capture") {
                Stepper(value: $settings.contextRadius, in: 0...4000, step: 100) {
                    Text("Context window: \(settings.contextRadius) characters before and after the selection")
                }
                Text("Sent to the LLM so it can match tone and terminology. 0 disables context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Toggle("Save runs to history", isOn: $settings.historyEnabled)
                Stepper(value: $settings.historyLimit, in: 50...5000, step: 50) {
                    Text("Keep the last \(settings.historyLimit) runs")
                }
            }

            Section("App") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }

    private var accessibilityGranted: Bool {
        _ = permissionCheck // dependency so "Recheck" re-renders
        return controller.accessibilityGranted
    }
}
