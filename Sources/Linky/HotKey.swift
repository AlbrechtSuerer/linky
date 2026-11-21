import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut. Carbon hot keys need no Accessibility permission.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32   // Carbon modifier mask
    var key: String         // display name of the key

    static let `default` = Shortcut(
        keyCode: UInt32(kVK_ANSI_L),
        modifiers: UInt32(controlKey | optionKey | cmdKey),
        key: "L"
    )

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + key
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { f.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { f.insert(.command) }
        return f
    }

    /// Builds a shortcut from a key press, or nil if it is not usable as a global shortcut.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }

        let code = Int(event.keyCode)
        let isFunctionKey = Self.functionKeys[code] != nil
        // Needs ⌃, ⌥ or ⌘ – unless it is an F-key.
        guard isFunctionKey || m & UInt32(controlKey | optionKey | cmdKey) != 0 else { return nil }

        let name = Self.functionKeys[code] ?? Self.specialKeys[code]
            ?? event.charactersIgnoringModifiers?.uppercased()
        guard let name, !name.isEmpty else { return nil }
        self.init(keyCode: UInt32(code), modifiers: m, key: name)
    }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    private static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19",
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    ]
}

final class HotKey {
    static let shared = HotKey()
    var handler: (() -> Void)?

    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4C4E4B59), id: 1) // 'LNKY'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.shared.handler?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
