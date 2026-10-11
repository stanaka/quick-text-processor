import AppKit
import QTPCore
import SwiftUI

/// Click-to-record hotkey control for Settings. While recording, the current
/// global hotkey is paused so it cannot fire mid-recording; Esc cancels.
struct HotkeyRecorderView: View {
    @EnvironmentObject private var controller: AppController
    @EnvironmentObject private var settings: SettingsStore

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleRecording) {
                Text(isRecording ? "Press shortcut… (esc cancels)" : settings.hotkey.displayString)
                    .frame(minWidth: 160)
            }
            if controller.hotkeyRegistrationFailed {
                Label("Could not register (in use by another app?)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        controller.setHotkeyPaused(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil // swallow while recording
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if isRecording {
            isRecording = false
            controller.setHotkeyPaused(false)
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 { // esc
            stopRecording()
            return
        }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= KeyCombo.cmd }
        if event.modifierFlags.contains(.shift) { modifiers |= KeyCombo.shift }
        if event.modifierFlags.contains(.option) { modifiers |= KeyCombo.option }
        if event.modifierFlags.contains(.control) { modifiers |= KeyCombo.control }

        let combo = KeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
        guard combo.hasModifiers || Self.functionKeyCodes.contains(combo.keyCode) else {
            NSSound.beep() // bare keys make terrible global hotkeys
            return
        }
        settings.hotkey = combo
        stopRecording()
    }

    private static let functionKeyCodes: Set<UInt32> =
        [96, 97, 98, 99, 100, 101, 103, 105, 107, 109, 111, 113, 118, 120, 122]
}
