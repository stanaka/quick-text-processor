import AppKit
import ApplicationServices
import QTPCore

/// What the hotkey pipeline works on: the captured text plus (when it came
/// from Accessibility) the focused element and owning app for insert-back.
struct CaptureContext {
    var text: CapturedText
    let element: AXUIElement?
    let app: NSRunningApplication?

    /// Insertion back into another app makes sense for hotkey captures only.
    var canInsert: Bool { text.source != .playground }
}

/// Reads the selection and its surrounding context from the frontmost app via
/// the Accessibility API. All ranges are UTF-16 CFRanges; the math lives in
/// QTPCore.TextContext.
enum AXCapture {

    /// Cap for the whole-value fallback so gigantic documents are never
    /// pulled across the AX connection.
    private static let wholeValueLimit = 200_000

    @MainActor
    static func isTrusted(promptIfNeeded: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// A failure carries why there is no usable AX selection, so callers can
    /// tell a curable one (a Chromium app whose AX tree is still off) from a
    /// missing permission or a genuinely empty selection before falling back
    /// to the clipboard.
    @MainActor
    static func capture(contextRadius: Int) -> Result<CaptureContext, CaptureFailure> {
        guard isTrusted(promptIfNeeded: true) else { return .failure(.notTrusted) }

        let frontmost = NSWorkspace.shared.frontmostApplication

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focusedRef) == .success,
              let focusedCF = focusedRef,
              CFGetTypeID(focusedCF) == AXUIElementGetTypeID() else {
            return .failure(.noFocusedElement)
        }
        let element = focusedCF as! AXUIElement

        // Never read out of password fields.
        if (copyAttribute(element, kAXRoleAttribute) as? String) == "AXSecureTextField" {
            return .failure(.secureField)
        }

        // A missing attribute and an empty selection look alike to the user;
        // keeping them apart is what makes the logs diagnosable.
        guard let selected = copyAttribute(element, kAXSelectedTextAttribute) as? String else {
            return .failure(.selectionAttributeMissing)
        }
        guard !selected.isEmpty else {
            return .failure(.emptySelection)
        }

        var before = ""
        var after = ""
        if let selection = selectedRange(of: element) {
            let total = (copyAttribute(element, kAXNumberOfCharactersAttribute) as? Int) ?? Int.max
            let beforeWindow = TextContext.beforeRange(selectionLocation: selection.location,
                                                       radius: contextRadius)
            let afterWindow = TextContext.afterRange(selectionLocation: selection.location,
                                                     selectionLength: selection.length,
                                                     radius: contextRadius,
                                                     totalLength: total)
            let beforeFetched = stringForRange(element,
                                               location: beforeWindow.location,
                                               length: beforeWindow.length)
            let afterFetched = stringForRange(element,
                                              location: afterWindow.location,
                                              length: afterWindow.length)

            // Zero-length windows "succeed" without querying the app, so only
            // a nonzero-length fetch proves AXStringForRange support; without
            // that proof, fall through to the whole-value slice (unless both
            // windows are legitimately empty).
            let parameterizedWorks =
                (beforeWindow.length > 0 && beforeFetched != nil)
                || (afterWindow.length > 0 && afterFetched != nil)
            let nothingToFetch = beforeWindow.length == 0 && afterWindow.length == 0

            if parameterizedWorks || nothingToFetch {
                before = TextContext.trimReplacementEdges(beforeFetched ?? "")
                after = TextContext.trimReplacementEdges(afterFetched ?? "")
            } else if total < wholeValueLimit,
                      let full = copyAttribute(element, kAXValueAttribute) as? String {
                // Apps without AXStringForRange: slice the whole value once.
                let windows = TextContext.contextWindows(fullText: full,
                                                         selectionLocation: selection.location,
                                                         selectionLength: selection.length,
                                                         radius: contextRadius)
                before = windows.before
                after = windows.after
            }
        }

        let text = CapturedText(selected: selected,
                                before: before,
                                after: after,
                                appName: frontmost?.localizedName,
                                bundleID: frontmost?.bundleIdentifier,
                                source: .accessibility)
        return .success(CaptureContext(text: text, element: element, app: frontmost))
    }

    // MARK: - AX plumbing

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else {
            return nil
        }
        return ref
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXSelectedTextRangeAttribute as CFString,
                                            &ref) == .success,
              let cf = ref,
              CFGetTypeID(cf) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = cf as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    /// Fetches a text window via the parameterized AXStringForRange attribute
    /// (cheap even in huge documents). Zero-length windows succeed as "".
    /// nil = the app does not support the parameterized attribute.
    private static func stringForRange(_ element: AXUIElement,
                                       location: Int,
                                       length: Int) -> String? {
        guard length > 0 else { return "" }
        var range = CFRange(location: location, length: length)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var out: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            parameter,
            &out)
        guard status == .success else { return nil }
        return out as? String
    }
}
