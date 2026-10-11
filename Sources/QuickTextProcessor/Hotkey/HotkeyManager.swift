import AppKit
import Carbon.HIToolbox
import QTPCore

/// Registers the global hotkey via Carbon's RegisterEventHotKey — reliable,
/// sandbox-free, and (unlike CGEvent taps) does not require the Accessibility
/// permission just to receive the key press.
@MainActor
final class HotkeyManager {

    /// Called on the main actor when the hotkey fires.
    var onHotkey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var currentCombo: KeyCombo?
    private var isPaused = false
    /// noErr when the last registration attempt succeeded.
    private(set) var lastRegistrationStatus: OSStatus = noErr

    func register(_ combo: KeyCombo) {
        currentCombo = combo
        applyRegistration()
    }

    /// Temporarily releases the hotkey (used while recording a new one).
    func pause() {
        isPaused = true
        applyRegistration()
    }

    func resume() {
        isPaused = false
        applyRegistration()
    }

    private func applyRegistration() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        guard !isPaused, let combo = currentCombo else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotkeySignature, id: 1)
        lastRegistrationStatus = RegisterEventHotKey(combo.keyCode,
                                                     combo.carbonModifiers,
                                                     hotKeyID,
                                                     GetEventDispatcherTarget(),
                                                     0,
                                                     &ref)
        if lastRegistrationStatus == noErr {
            hotKeyRef = ref
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(),
                            hotkeyEventHandler,
                            1,
                            &eventType,
                            Unmanaged.passUnretained(self).toOpaque(),
                            &handlerRef)
    }

    /// Carbon calls back through a C function pointer; hop onto the main actor.
    nonisolated fileprivate func fire() {
        Task { @MainActor [weak self] in
            self?.onHotkey?()
        }
    }
}

// "QTPH"
private let hotkeySignature: FourCharCode = 0x5154_5048

/// C-convention Carbon callback: no Swift captures allowed, so the manager
/// arrives through userData.
private func hotkeyEventHandler(_ call: EventHandlerCallRef?,
                                _ event: EventRef?,
                                _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr, hotKeyID.signature == hotkeySignature else { return noErr }
    Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().fire()
    return noErr
}
