import XCTest
@testable import QTPCore

final class ConfirmationKeysTests: XCTestCase {

    func testReturnAndKeypadEnterInsert() {
        XCTAssertEqual(ConfirmationKeys.action(forKeyCode: 36), .insert)
        XCTAssertEqual(ConfirmationKeys.action(forKeyCode: 76), .insert)
    }

    func testEscapeDismisses() {
        XCTAssertEqual(ConfirmationKeys.action(forKeyCode: 53), .dismiss)
    }

    func testOtherKeysPassThrough() {
        // Arrows, space, letters, digits — none may be swallowed.
        for keyCode: UInt16 in [125, 126, 123, 124, 49, 0, 9, 18, 51] {
            XCTAssertNil(ConfirmationKeys.action(forKeyCode: keyCode),
                         "keyCode \(keyCode) must pass through")
        }
    }
}
