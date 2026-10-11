import AppKit
import ApplicationServices
import os

/// Chromium keeps its accessibility tree disabled until an assistive
/// technology asks for it, so in Electron apps (VS Code, Slack, ...) the
/// focused element exposes no text attributes and every capture degrades to
/// the clipboard. Electron's documented opt-in is setting
/// AXManualAccessibility on the application element.
///
/// Accepting the attribute is not the same as having a tree: Electron
/// debounces the actual switch-on by 2 seconds, so callers must poll
/// `isTreeReady(pid:)` rather than assume success is immediate.
///
/// We deliberately do NOT set the legacy AXEnhancedUserInterface: it is
/// sticky on the target app and known to break window moving/resizing in
/// Electron apps and to disturb Chrome's window management. The cost is that
/// plain Google Chrome, which ignores AXManualAccessibility, may still fall
/// back to the clipboard.
@MainActor
enum ElectronAccessibility {

    private static let manualAccessibilityAttribute = "AXManualAccessibility" as CFString

    /// What asking an app to switch its tree on told us about that app.
    enum EnableResult {
        /// The attribute was accepted just now; the tree is still being built.
        case newlyEnabled
        /// We switched this app on earlier in the session.
        case alreadyEnabled
        /// The app does not implement the attribute — every native app.
        case unsupported
    }

    /// pids switched on during this session. This suppresses the redundant AX
    /// write, and nothing more: an already-enabled app is still worth
    /// re-capturing, because a tree that is up can still lag a window switch.
    private static var enabledPIDs: Set<pid_t> = []
    private static var terminationObserver: NSObjectProtocol?

    static func enable(pid: pid_t) -> EnableResult {
        guard !enabledPIDs.contains(pid) else {
            Log.capture.notice("AXManualAccessibility already enabled for pid \(pid, privacy: .public)")
            return .alreadyEnabled
        }
        installTerminationObserverIfNeeded()

        let appElement = AXUIElementCreateApplication(pid)
        let status = AXUIElementSetAttributeValue(appElement,
                                                  manualAccessibilityAttribute,
                                                  kCFBooleanTrue as CFTypeRef)
        guard status == .success else {
            Log.capture.notice("AXManualAccessibility rejected by pid \(pid, privacy: .public): \(status.rawValue, privacy: .public)")
            return .unsupported
        }
        enabledPIDs.insert(pid)
        Log.capture.notice("Enabled AXManualAccessibility for pid \(pid, privacy: .public)")
        return .newlyEnabled
    }

    /// Whether the app's tree is actually built yet.
    ///
    /// Electron answers a read of AXManualAccessibility with whether its mode
    /// is `kAXModeComplete`, so this reports the real state rather than the
    /// fact that our write was accepted 2 seconds ago. Polling it lets a
    /// capture return the moment the tree appears instead of always paying
    /// the full budget.
    static func isTreeReady(pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement,
                                            manualAccessibilityAttribute,
                                            &value) == .success,
              let number = value as? NSNumber else {
            return false
        }
        return number.boolValue
    }

    /// pids are reused, so forget an app once it quits — the next launch has
    /// to be switched on again.
    private static func installTerminationObserverIfNeeded() {
        guard terminationObserver == nil else { return }
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main) { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication else { return }
                let pid = app.processIdentifier
                Task { @MainActor in
                    enabledPIDs.remove(pid)
                }
            }
    }
}
