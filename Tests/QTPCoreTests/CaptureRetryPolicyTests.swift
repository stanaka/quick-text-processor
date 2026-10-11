import XCTest
@testable import QTPCore

final class CaptureRetryPolicyTests: XCTestCase {

    func testFirstEnableBudgetOutlastsElectronsTwoSecondDebounce() {
        // Electron schedules the actual switch-on behind a 2.0s debounce in
        // enableScreenReaderCompleteModeAfterDelay:, so a budget under that
        // expires before the tree exists — the bug that made the first
        // version of this fix inert. The wait ends early once the tree
        // reports ready, so a generous cap costs nothing in practice.
        XCTAssertGreaterThan(CaptureRetryPolicy.firstEnableBudgetMilliseconds, 2_500)
    }

    func testAlreadyEnabledBudgetStaysShort() {
        // Paid on presses after the first, so it must stay imperceptible.
        XCTAssertGreaterThan(CaptureRetryPolicy.alreadyEnabledBudgetMilliseconds, 0)
        XCTAssertLessThanOrEqual(CaptureRetryPolicy.alreadyEnabledBudgetMilliseconds, 250)
    }

    func testPollIntervalDividesTheBudgetsUsefully() {
        let interval = CaptureRetryPolicy.pollIntervalMilliseconds
        XCTAssertGreaterThan(interval, 0)
        // At least one re-check inside the shorter budget, and enough of them
        // in the longer one to spot the tree promptly once it appears.
        XCTAssertLessThanOrEqual(interval, CaptureRetryPolicy.alreadyEnabledBudgetMilliseconds)
        XCTAssertGreaterThanOrEqual(CaptureRetryPolicy.firstEnableBudgetMilliseconds / interval, 10)
    }

    func testPostTreeReadyGraceIsBoundedAndSmall() {
        // Bounds the app-has-nothing-for-us case (a VS Code editor at default
        // settings) so it does not stall for the whole budget.
        XCTAssertGreaterThan(CaptureRetryPolicy.postTreeReadyGraceMilliseconds, 0)
        XCTAssertLessThan(CaptureRetryPolicy.postTreeReadyGraceMilliseconds,
                          CaptureRetryPolicy.firstEnableBudgetMilliseconds)
    }

    func testEveryDisabledTreeShapeTriggersTheEnable() {
        // The three ways a disabled Chromium tree can present.
        XCTAssertTrue(CaptureRetryPolicy.shouldAttemptAccessibilityEnable(after: .noFocusedElement))
        XCTAssertTrue(CaptureRetryPolicy.shouldAttemptAccessibilityEnable(after: .selectionAttributeMissing))
        XCTAssertTrue(CaptureRetryPolicy.shouldAttemptAccessibilityEnable(after: .emptySelection))
    }

    func testPermissionAndSecureFieldNeverRetry() {
        // No retry can conjure a permission, and a password field is a real
        // answer we must respect.
        XCTAssertFalse(CaptureRetryPolicy.shouldAttemptAccessibilityEnable(after: .notTrusted))
        XCTAssertFalse(CaptureRetryPolicy.shouldAttemptAccessibilityEnable(after: .secureField))
    }

    func testAlreadyEnabledRetriesOnlyTreeShapedFailures() {
        // An app switched on earlier still gets a look: its tree can lag a
        // window or tab switch.
        XCTAssertTrue(CaptureRetryPolicy.shouldRetryWhenAlreadyEnabled(after: .noFocusedElement))
        XCTAssertTrue(CaptureRetryPolicy.shouldRetryWhenAlreadyEnabled(after: .selectionAttributeMissing))
    }

    func testAlreadyEnabledTreatsEmptySelectionAsTheRealAnswer() {
        // The narrowing that keeps later presses instant: with the tree up, an
        // element that exposes the attribute and answers "" means the user
        // genuinely has nothing selected.
        XCTAssertFalse(CaptureRetryPolicy.shouldRetryWhenAlreadyEnabled(after: .emptySelection))
        XCTAssertFalse(CaptureRetryPolicy.shouldRetryWhenAlreadyEnabled(after: .notTrusted))
        XCTAssertFalse(CaptureRetryPolicy.shouldRetryWhenAlreadyEnabled(after: .secureField))
    }

    func testAlreadyEnabledRetrySetIsSubsetOfEnableSet() {
        // A failure we would not switch the tree on for must never trigger a
        // re-check either.
        let failures: [CaptureFailure] = [.notTrusted, .noFocusedElement, .secureField,
                                          .selectionAttributeMissing, .emptySelection]
        for failure in failures where CaptureRetryPolicy.shouldRetryWhenAlreadyEnabled(after: failure) {
            XCTAssertTrue(CaptureRetryPolicy.shouldAttemptAccessibilityEnable(after: failure),
                          "\(failure) retries when already enabled but would never be enabled")
        }
    }
}
