import AppKit
import Carbon.HIToolbox

/// One system-wide hotkey, registered through Carbon's `RegisterEventHotKey`.
///
/// Carbon is used on purpose: unlike a `CGEventTap`, it needs no
/// Accessibility permission, which matters for a menu bar utility that would
/// otherwise ask for one at first launch.
@MainActor
final class GlobalHotKey {
    /// Whether this process accepted the registration. It says nothing about
    /// *other* apps: when two of them register the same combination, the
    /// first one in wins and the second still registers happily, it just
    /// never fires. That conflict is undetectable from here, which is why the
    /// shortcut is user-configurable.
    private(set) var isRegistered = false

    fileprivate let onPress: () -> Void
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    init(combo: KeyCombo, onPress: @escaping () -> Void) {
        self.onPress = onPress
        register(keyCode: combo.keyCode, modifiers: combo.carbonModifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handler: EventHandlerRef?
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyPressed,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        eventHandler = handler

        var reference: EventHotKeyRef?
        let registered = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        hotKey = reference

        isRegistered = installed == noErr && registered == noErr
        if !isRegistered {
            NSLog("mdNotch: hotkey registration failed (install %d, register %d)", installed, registered)
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// Four-char code 'mdNc', so our hotkey is distinguishable from anyone
    /// else's in the same event target.
    private static let signature = OSType(0x6D64_4E63)
}

/// C callback: no captures allowed, so `self` travels through `userData`.
private let hotKeyPressed: EventHandlerUPP = { _, _, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            hotKey.onPress()
        }
    }
    return noErr
}
