import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut the user picked: one physical key plus its modifiers.
///
/// The key is stored as a *physical* key code, which is what
/// `RegisterEventHotKey` wants. Its label is therefore derived from the
/// current keyboard layout every time it is displayed, never persisted — on an
/// AZERTY layout, code 6 reads "Z" where QWERTY reads "W", and a stored label
/// would go stale the moment the layout changes.
struct KeyCombo: Equatable {
    let keyCode: UInt32
    let modifiers: NSEvent.ModifierFlags

    /// ⌘⇧V — "paste", one modifier away.
    static let defaultPaste = KeyCombo(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: [.command, .shift]
    )

    /// Modifiers that make a global shortcut safe to register. Shift alone
    /// isn't one of them: `⇧A` would swallow a capital A system-wide.
    private static let requiredAny: NSEvent.ModifierFlags = [.command, .control, .option]

    /// Rejects combinations that would eat ordinary typing.
    var isValid: Bool {
        !modifiers.intersection(Self.requiredAny).isEmpty
    }

    /// Carbon's own modifier bit field, as `RegisterEventHotKey` expects.
    var carbonModifiers: UInt32 {
        var carbon: Int = 0
        if modifiers.contains(.command) { carbon |= cmdKey }
        if modifiers.contains(.shift) { carbon |= shiftKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.control) { carbon |= controlKey }
        return UInt32(carbon)
    }

    /// The shortcut as macOS writes it: `⌘⇧V`.
    var displayString: String {
        Self.symbols(for: modifiers) + Self.keyLabel(for: keyCode)
    }

    /// The key as an `NSMenuItem.keyEquivalent`, or nil for a key that types
    /// no character and therefore cannot be one.
    var menuKeyEquivalent: String? {
        Self.character(for: keyCode)?.lowercased()
    }

    /// Modifier symbols in the order macOS shows them.
    static func symbols(for modifiers: NSEvent.ModifierFlags) -> String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text
    }
}

// MARK: - Persistence

extension KeyCombo {
    /// Stored as two plain integers, so a combination survives as what it is
    /// rather than as a string nobody can re-parse.
    ///
    /// "No shortcut" needs its own representation: an *absent* key means
    /// "never set" and must fall back to the default, so a cleared shortcut is
    /// written as a negative key code instead.
    static func read(
        from defaults: UserDefaults,
        keyCodeKey: String,
        modifiersKey: String,
        fallback: KeyCombo?
    ) -> KeyCombo? {
        guard let code = defaults.object(forKey: keyCodeKey) as? Int else { return fallback }
        guard code >= 0 else { return nil }
        return KeyCombo(
            keyCode: UInt32(code),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: modifiersKey)))
        )
    }

    static func write(
        _ combo: KeyCombo?,
        to defaults: UserDefaults,
        keyCodeKey: String,
        modifiersKey: String
    ) {
        defaults.set(combo.map { Int($0.keyCode) } ?? -1, forKey: keyCodeKey)
        defaults.set(Int(combo?.modifiers.rawValue ?? 0), forKey: modifiersKey)
    }
}

// MARK: - Key labels

extension KeyCombo {
    /// Keys that produce no character, named the way macOS names them.
    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_ANSI_KeypadEnter: "⌤",
        kVK_Tab: "⇥",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "↖",
        kVK_End: "↘",
        kVK_PageUp: "⇞",
        kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func keyLabel(for keyCode: UInt32) -> String {
        if let named = namedKeys[Int(keyCode)] { return named }
        if let character = character(for: keyCode) { return character.uppercased() }
        return "#\(keyCode)"
    }

    /// Asks the current keyboard layout what character a physical key types,
    /// with no modifiers applied.
    private static func character(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0, // no modifiers: we want the key's own label
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
