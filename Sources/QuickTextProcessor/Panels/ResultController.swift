import AppKit
import QTPCore
import SwiftUI

/// Owns the floating result panel. Unlike the palette it is shown WITHOUT
/// taking keyboard focus (orderFrontRegardless), so the user can keep typing
/// in the target app while the answer streams in; buttons work on click.
/// Auto-insert runs additionally end in a confirmation state: the panel takes
/// key focus (non-activating, like the palette) and waits for ⏎ / esc.
@MainActor
final class ResultController: NSObject, NSWindowDelegate {

    let model = StreamRunModel()

    /// Wired by AppController for the current run.
    var onInsert: ((String) -> Void)?
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    private var panel: NSPanel?
    private var keyMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    func present(taskName: String, canInsert: Bool) {
        endConfirmation()
        model.begin(title: taskName, canInsert: canInsert)
        let panel = ensurePanel()
        panel.title = taskName
        if !panel.isVisible {
            positionPanelNearMouse(panel)
        }
        panel.orderFrontRegardless()
    }

    /// Shows an error without a preceding streaming phase (e.g. auto-insert
    /// runs that failed before producing output).
    func presentError(taskName: String, message: String) {
        present(taskName: taskName, canInsert: false)
        model.fail(message)
    }

    func hide() {
        onDismiss?()
        endConfirmation()
        panel?.orderOut(nil)
    }

    // MARK: - Insert confirmation

    /// Arms the "waiting for the user's response" state after an auto-insert
    /// run finished: the panel becomes key (without activating this app, so
    /// the target app keeps its focused element for insert-back) and ⏎ / esc
    /// decide what happens. Buttons keep working on click throughout.
    func beginConfirmation() {
        guard model.state == .done,
              model.canInsert,
              !model.text.isEmpty,
              let panel, panel.isVisible else { return }
        model.awaitingConfirmation = true
        installKeyMonitor()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Disarms the confirmation state without touching the panel or its text.
    func endConfirmation() {
        removeKeyMonitor()
        model.awaitingConfirmation = false
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.model.awaitingConfirmation else { return event }
            guard let action = ConfirmationKeys.action(forKeyCode: event.keyCode) else {
                return event
            }
            switch action {
            case .insert:
                // Disarm first: insertText() hides the panel, and the
                // resulting resign-key must not re-enter this path.
                self.endConfirmation()
                self.insertText()
            case .dismiss:
                self.endConfirmation()
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let hosting = NSHostingView(rootView: ResultView(
            model: model,
            onCopy: { [weak self] in self?.copyText() },
            onInsert: { [weak self] in self?.insertText() },
            onRetry: { [weak self] in
                self?.endConfirmation()
                self?.onRetry?()
            },
            onClose: { [weak self] in self?.hide() }
        ))
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.setContentSize(NSSize(width: 460, height: 300))
        panel.delegate = self
        self.panel = panel
        return panel
    }

    private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.text, forType: .string)
    }

    private func insertText() {
        onInsert?(model.text)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    /// Click-away while waiting: hand the keyboard back to the target app but
    /// keep the panel (and the answer) visible for the buttons.
    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        endConfirmation()
    }
}
