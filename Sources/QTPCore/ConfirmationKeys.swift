import Foundation

/// Maps key codes to the actions of the result panel's confirmation state
/// (an auto-insert run waiting for the user's response). Pure so the app's
/// key monitor stays a one-liner and the mapping is unit-testable.
public enum ConfirmationKeys {

    public enum Action: Equatable {
        case insert
        case dismiss
    }

    /// Return / keypad enter confirm the insert; esc dismisses. Every other
    /// key is nil so the caller passes it through untouched.
    public static func action(forKeyCode keyCode: UInt16) -> Action? {
        switch keyCode {
        case 36, 76: // return / keypad enter
            return .insert
        case 53: // esc
            return .dismiss
        default:
            return nil
        }
    }
}
