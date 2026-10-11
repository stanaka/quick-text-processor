import Foundation

/// A global hotkey: a Carbon virtual key code plus Carbon modifier flags.
/// Kept UI-framework-free; the raw values match Carbon's `cmdKey`/`shiftKey`/
/// `optionKey`/`controlKey` so the app target can pass them straight to
/// `RegisterEventHotKey`.
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    // Carbon modifier masks (Events.h).
    public static let cmd: UInt32 = 0x0100
    public static let shift: UInt32 = 0x0200
    public static let option: UInt32 = 0x0800
    public static let control: UInt32 = 0x1000

    /// Default hotkey: Control + Option + Space.
    public static let `default` = KeyCombo(keyCode: 49, carbonModifiers: control | option)

    /// True when at least one modifier is present (bare keys make bad hotkeys).
    public var hasModifiers: Bool {
        carbonModifiers & (Self.cmd | Self.shift | Self.option | Self.control) != 0
    }

    /// Human-readable representation, e.g. "⌃⌥Space".
    public var displayString: String {
        var s = ""
        if carbonModifiers & Self.control != 0 { s += "⌃" }
        if carbonModifiers & Self.option != 0 { s += "⌥" }
        if carbonModifiers & Self.shift != 0 { s += "⇧" }
        if carbonModifiers & Self.cmd != 0 { s += "⌘" }
        s += Self.keyName(for: keyCode)
        return s
    }

    /// Names for common Carbon virtual key codes (US layout for letters/symbols).
    public static func keyName(for keyCode: UInt32) -> String {
        if let name = keyNames[keyCode] { return name }
        return "Key(\(keyCode))"
    }

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "Escape",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12",
        113: "F15", 114: "Help", 115: "Home", 116: "PageUp",
        117: "ForwardDelete", 118: "F4", 119: "End", 120: "F2",
        121: "PageDown", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
