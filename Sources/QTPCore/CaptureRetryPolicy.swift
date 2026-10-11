import Foundation

/// Why an Accessibility capture attempt produced no usable selection.
/// `Error` so it can be the failure type of `AXCapture`'s `Result`.
public enum CaptureFailure: Error, Equatable, Sendable {
    /// The process is not trusted for Accessibility (no permission).
    case notTrusted
    /// The system-wide focused-element lookup failed.
    case noFocusedElement
    /// The focused element is a password field: never read.
    case secureField
    /// The focused element has no selected-text attribute at all — the
    /// signature of a Chromium/Electron app whose AX tree is still disabled.
    case selectionAttributeMissing
    /// The attribute exists but the selection is empty.
    case emptySelection
}

/// Pure policy for the "enable the Chromium/Electron AX tree and retry"
/// dance. Chromium keeps its accessibility tree off until an assistive
/// technology asks for it, and builds it asynchronously once asked.
public enum CaptureRetryPolicy {

    /// How long to keep re-checking after newly switching an app's tree on.
    ///
    /// Electron does NOT enable the tree when it accepts the attribute: its
    /// `accessibilitySetValue:forAttribute:` schedules
    /// `enableScreenReaderCompleteMode` behind a 2.0s debounce (it waits out
    /// the spurious AXEnhancedUserInterface toggles macOS emits since
    /// Sonoma). Anything under that expires before the tree exists — the
    /// reason the first version of this fix never worked. Do not shrink this
    /// below ~2.5s without re-reading electron_application.mm.
    ///
    /// The wait ends as soon as the tree reports ready, so this is a cap and
    /// not a cost, and only the first capture per app launch can pay it.
    public static let firstEnableBudgetMilliseconds = 2600

    /// The budget for an app whose tree we switched on earlier. It is already
    /// built, so this only absorbs focus jitter between the keystroke and the
    /// capture.
    public static let alreadyEnabledBudgetMilliseconds = 150

    /// Gap between re-checks within either budget.
    public static let pollIntervalMilliseconds = 100

    /// How much longer to look after the tree reports ready but the focused
    /// element still exposes no selection.
    ///
    /// This bounds the case where an app's tree comes up and still has
    /// nothing for us — a VS Code editor at default settings, whose selection
    /// never reaches the DOM — so it costs a grace period rather than the
    /// whole budget.
    public static let postTreeReadyGraceMilliseconds = 300

    /// Which failures are worth switching the tree on for. A disabled
    /// Chromium tree can surface as any of three shapes — no focused element,
    /// a focused element with no text attributes, or a stub element answering
    /// with an empty string — so all three try. `.emptySelection` is included
    /// on purpose: guessing wrong there would make the whole fix silently
    /// inert, while the cost is bounded (only apps that accept the attribute
    /// wait, and only on the first capture after they launch).
    ///
    /// A secure field is a real answer we must respect, and a missing
    /// permission needs the user, not a retry.
    public static func shouldAttemptAccessibilityEnable(after failure: CaptureFailure) -> Bool {
        switch failure {
        case .noFocusedElement, .selectionAttributeMissing, .emptySelection:
            return true
        case .notTrusted, .secureField:
            return false
        }
    }

    /// Whether to re-check an app whose tree was switched on earlier.
    ///
    /// Narrower than `shouldAttemptAccessibilityEnable` by one case: once the
    /// tree is up, an element that exposes the attribute and answers "" is a
    /// real answer, so `.emptySelection` returns immediately instead of
    /// stalling every press. The two tree-shaped failures still retry — the
    /// tree can lag a window or tab switch.
    ///
    /// That narrowing is what keeps a VS Code editor at default settings
    /// responsive: it answers with an empty string on every press, so without
    /// this it would stall before every clipboard fallback.
    public static func shouldRetryWhenAlreadyEnabled(after failure: CaptureFailure) -> Bool {
        switch failure {
        case .noFocusedElement, .selectionAttributeMissing:
            return true
        case .emptySelection, .notTrusted, .secureField:
            return false
        }
    }
}
