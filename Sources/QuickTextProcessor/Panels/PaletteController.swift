import AppKit
import QTPCore
import SwiftUI

/// Owns the floating task palette: shows it near the mouse, drives selection
/// from a local key monitor (↑/↓, 1–9, ⏎, esc), and dismisses on click-away.
/// The panel is key (it receives keys) but never activates the app.
@MainActor
final class PaletteController: NSObject, NSWindowDelegate {

    private let model = PaletteModel()
    private var panel: KeyablePanel?
    private var keyMonitor: Any?
    private var onPick: ((PromptTask) -> Void)?
    private var onCancel: (() -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(tasks: [PromptTask],
              sourceLabel: String,
              previewText: String,
              beforeText: String,
              afterText: String,
              isClipboardSource: Bool,
              emptyMessage: String?,
              onPick: @escaping (PromptTask) -> Void,
              onCancel: @escaping () -> Void) {
        self.onPick = onPick
        self.onCancel = onCancel

        model.tasks = tasks
        model.selectedIndex = 0
        model.sourceLabel = sourceLabel
        model.previewText = previewText
        model.beforeText = beforeText
        model.afterText = afterText
        model.isClipboardSource = isClipboardSource
        model.emptyMessage = emptyMessage

        let panel = ensurePanel()
        sizeToFit(panel)
        positionPanelNearMouse(panel)
        installKeyMonitor()
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        let callback = onCancel
        clearCallbacks()
        finishPresentation()
        callback?()
    }

    // MARK: - Panel plumbing

    private func ensurePanel() -> KeyablePanel {
        if let panel { return panel }
        let hosting = NSHostingView(rootView: PaletteView(model: model) { [weak self] index in
            self?.pick(index: index)
        })
        let panel = KeyablePanel.makeFloating(content: hosting)
        panel.delegate = self
        self.panel = panel
        return panel
    }

    private func sizeToFit(_ panel: KeyablePanel) {
        guard let hosting = panel.contentView else { return }
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        if size.width < 100 || size.height < 60 {
            size = NSSize(width: 340, height: 240)
        }
        panel.setContentSize(size)
    }

    private func pick(index: Int) {
        guard model.emptyMessage == nil, model.tasks.indices.contains(index) else { return }
        let task = model.tasks[index]
        let callback = onPick
        // Clear before orderOut: hiding the panel fires windowDidResignKey,
        // which must not turn a pick into a cancel.
        clearCallbacks()
        finishPresentation()
        callback?(task)
    }

    private func finishPresentation() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    private func clearCallbacks() {
        onPick = nil
        onCancel = nil
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return self.handle(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 53: // esc
            dismiss()
            return nil
        case 36, 76: // return / keypad enter
            pick(index: model.selectedIndex)
            return nil
        case 125: // down
            if !model.tasks.isEmpty {
                model.selectedIndex = min(model.selectedIndex + 1, model.tasks.count - 1)
            }
            return nil
        case 126: // up
            model.selectedIndex = max(model.selectedIndex - 1, 0)
            return nil
        default:
            if let characters = event.charactersIgnoringModifiers,
               characters.count == 1,
               let digit = Int(characters),
               (1...9).contains(digit),
               digit <= model.tasks.count {
                pick(index: digit - 1)
                return nil
            }
            return event
        }
    }

    // MARK: - NSWindowDelegate

    /// Click-away (panel loses key status) cancels.
    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel, isVisible else { return }
        dismiss()
    }
}
