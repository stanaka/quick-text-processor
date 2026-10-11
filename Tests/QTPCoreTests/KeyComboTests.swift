import XCTest
@testable import QTPCore

final class KeyComboTests: XCTestCase {

    func testDefaultDisplayString() {
        XCTAssertEqual(KeyCombo.default.displayString, "⌃⌥Space")
    }

    func testModifierSymbolOrderAndKeys() {
        let combo = KeyCombo(keyCode: 9, // V
                             carbonModifiers: KeyCombo.cmd | KeyCombo.shift | KeyCombo.option | KeyCombo.control)
        XCTAssertEqual(combo.displayString, "⌃⌥⇧⌘V")
    }

    func testUnknownKeyCodeFallback() {
        let combo = KeyCombo(keyCode: 200, carbonModifiers: KeyCombo.cmd)
        XCTAssertEqual(combo.displayString, "⌘Key(200)")
    }

    func testHasModifiers() {
        XCTAssertTrue(KeyCombo.default.hasModifiers)
        XCTAssertFalse(KeyCombo(keyCode: 49, carbonModifiers: 0).hasModifiers)
    }

    func testCodableRoundTrip() throws {
        let combo = KeyCombo(keyCode: 122, carbonModifiers: KeyCombo.option)
        let data = try JSONEncoder().encode(combo)
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: data)
        XCTAssertEqual(decoded, combo)
    }
}
