import AppKit
import ApplicationServices

/// Inserts the LLM result back into the target app: first by setting the AX
/// selected text (clean, no clipboard involved), else by a pasteboard +
/// synthesized ⌘V round trip with best-effort clipboard restore.
///
/// IMPORTANT: callers must order out the app's own panels BEFORE calling —
/// while one of our panels is the key window, the synthesized ⌘V would land
/// in this app instead of the target.
enum TextInsertion {

    @MainActor
    static func insert(_ text: String, into context: CaptureContext?) async {
        guard !text.isEmpty else { return }
        if let element = context?.element, axReplaceSelection(element, with: text) {
            return
        }
        await pasteFallback(text, app: context?.app)
    }

    // MARK: - AX path

    private static func axReplaceSelection(_ element: AXUIElement, with text: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element,
                                             kAXSelectedTextAttribute as CFString,
                                             &settable) == .success,
              settable.boolValue else {
            return false
        }
        return AXUIElementSetAttributeValue(element,
                                            kAXSelectedTextAttribute as CFString,
                                            text as CFString) == .success
    }

    // MARK: - Pasteboard path

    @MainActor
    private static func pasteFallback(_ text: String, app: NSRunningApplication?) async {
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotItems(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        // Make sure the target app has keyboard focus again.
        if let app, !app.isActive {
            app.activate(options: [])
        }
        try? await Task.sleep(nanoseconds: 80_000_000)

        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source,
                                virtualKey: 9, // kVK_ANSI_V
                                keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }

        // Give the target app time to consume the paste, then restore the
        // previous clipboard — unless someone else wrote to it meanwhile.
        try? await Task.sleep(nanoseconds: 300_000_000)
        if pasteboard.changeCount == ourChangeCount {
            restore(snapshot, to: pasteboard)
        }
    }

    private static func snapshotItems(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy[type] = data
                }
            }
            return copy
        }
    }

    private static func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]],
                                to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { typedData -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in typedData {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
