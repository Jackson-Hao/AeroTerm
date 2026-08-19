import Carbon
import RDPKit

enum RDPKeyMap {
    static let leftShift = RDPKeyboardScancode(code: 0x2A)
    static let rightShift = RDPKeyboardScancode(code: 0x36)
    static let leftControl = RDPKeyboardScancode(code: 0x1D)
    static let rightControl = RDPKeyboardScancode(code: 0x1D, isExtended: true)
    static let leftAlt = RDPKeyboardScancode(code: 0x38)
    static let rightAlt = RDPKeyboardScancode(code: 0x38, isExtended: true)
    static let leftWin = RDPKeyboardScancode(code: 0x5B, isExtended: true)
    static let rightWin = RDPKeyboardScancode(code: 0x5C, isExtended: true)
    static let capsLock = RDPKeyboardScancode(code: 0x3A)

    static let rightShiftKeyCode = UInt16(kVK_RightShift)
    static let rightControlKeyCode = UInt16(kVK_RightControl)
    static let rightOptionKeyCode = UInt16(kVK_RightOption)
    static let rightCommandKeyCode = UInt16(kVK_RightCommand)

    static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Shift), UInt16(kVK_RightShift),
        UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_Option), UInt16(kVK_RightOption),
        UInt16(kVK_Command), UInt16(kVK_RightCommand),
        UInt16(kVK_CapsLock)
    ]

    static func scancode(forMacKeyCode keyCode: UInt16) -> RDPKeyboardScancode? {
        guard keyCode < UInt16(table.count) else { return nil }
        return table[Int(keyCode)]
    }

    static func isFunctionKeyScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0xF700..<0xF900).contains(scalar.value)
    }

    private static let table: [RDPKeyboardScancode?] = makeTable()

    private static func makeTable() -> [RDPKeyboardScancode?] {
        var table = [RDPKeyboardScancode?](repeating: nil, count: 128)
        func set(_ key: Int, _ code: UInt16, extended: Bool = false) {
            guard table.indices.contains(key) else { return }
            table[key] = RDPKeyboardScancode(code: code, isExtended: extended)
        }

        set(kVK_ANSI_A, 0x1E)
        set(kVK_ANSI_S, 0x1F)
        set(kVK_ANSI_D, 0x20)
        set(kVK_ANSI_F, 0x21)
        set(kVK_ANSI_H, 0x23)
        set(kVK_ANSI_G, 0x22)
        set(kVK_ANSI_Z, 0x2C)
        set(kVK_ANSI_X, 0x2D)
        set(kVK_ANSI_C, 0x2E)
        set(kVK_ANSI_V, 0x2F)
        set(kVK_ANSI_B, 0x30)
        set(kVK_ANSI_Q, 0x10)
        set(kVK_ANSI_W, 0x11)
        set(kVK_ANSI_E, 0x12)
        set(kVK_ANSI_R, 0x13)
        set(kVK_ANSI_Y, 0x15)
        set(kVK_ANSI_T, 0x14)
        set(kVK_ANSI_1, 0x02)
        set(kVK_ANSI_2, 0x03)
        set(kVK_ANSI_3, 0x04)
        set(kVK_ANSI_4, 0x05)
        set(kVK_ANSI_6, 0x07)
        set(kVK_ANSI_5, 0x06)
        set(kVK_ANSI_Equal, 0x0D)
        set(kVK_ANSI_9, 0x0A)
        set(kVK_ANSI_7, 0x08)
        set(kVK_ANSI_Minus, 0x0C)
        set(kVK_ANSI_8, 0x09)
        set(kVK_ANSI_0, 0x0B)
        set(kVK_ANSI_RightBracket, 0x1B)
        set(kVK_ANSI_O, 0x18)
        set(kVK_ANSI_U, 0x16)
        set(kVK_ANSI_LeftBracket, 0x1A)
        set(kVK_ANSI_I, 0x17)
        set(kVK_ANSI_P, 0x19)
        set(kVK_Return, 0x1C)
        set(kVK_ANSI_L, 0x26)
        set(kVK_ANSI_J, 0x24)
        set(kVK_ANSI_Quote, 0x28)
        set(kVK_ANSI_K, 0x25)
        set(kVK_ANSI_Semicolon, 0x27)
        set(kVK_ANSI_Backslash, 0x2B)
        set(kVK_ANSI_Comma, 0x33)
        set(kVK_ANSI_Slash, 0x35)
        set(kVK_ANSI_N, 0x31)
        set(kVK_ANSI_M, 0x32)
        set(kVK_ANSI_Period, 0x34)
        set(kVK_Tab, 0x0F)
        set(kVK_Space, 0x39)
        set(kVK_ANSI_Grave, 0x29)
        set(kVK_Delete, 0x0E)
        set(kVK_Escape, 0x01)
        set(kVK_ISO_Section, 0x56)

        set(kVK_Command, 0x5B, extended: true)
        set(kVK_Shift, 0x2A)
        set(kVK_CapsLock, 0x3A)
        set(kVK_Option, 0x38)
        set(kVK_Control, 0x1D)
        set(kVK_RightCommand, 0x5C, extended: true)
        set(kVK_RightShift, 0x36)
        set(kVK_RightOption, 0x38, extended: true)
        set(kVK_RightControl, 0x1D, extended: true)

        set(kVK_ANSI_KeypadDecimal, 0x53)
        set(kVK_ANSI_KeypadMultiply, 0x37)
        set(kVK_ANSI_KeypadPlus, 0x4E)
        set(kVK_ANSI_KeypadClear, 0x45)
        set(kVK_ANSI_KeypadDivide, 0x35, extended: true)
        set(kVK_ANSI_KeypadEnter, 0x1C, extended: true)
        set(kVK_ANSI_KeypadMinus, 0x4A)
        set(kVK_ANSI_KeypadEquals, 0x0D)
        set(kVK_ANSI_Keypad0, 0x52)
        set(kVK_ANSI_Keypad1, 0x4F)
        set(kVK_ANSI_Keypad2, 0x50)
        set(kVK_ANSI_Keypad3, 0x51)
        set(kVK_ANSI_Keypad4, 0x4B)
        set(kVK_ANSI_Keypad5, 0x4C)
        set(kVK_ANSI_Keypad6, 0x4D)
        set(kVK_ANSI_Keypad7, 0x47)
        set(kVK_ANSI_Keypad8, 0x48)
        set(kVK_ANSI_Keypad9, 0x49)

        set(kVK_F5, 0x3F)
        set(kVK_F6, 0x40)
        set(kVK_F7, 0x41)
        set(kVK_F3, 0x3D)
        set(kVK_F8, 0x42)
        set(kVK_F9, 0x43)
        set(kVK_F11, 0x57)
        set(kVK_F13, 0x64)
        set(kVK_F16, 0x67)
        set(kVK_F14, 0x65)
        set(kVK_F10, 0x44)
        set(kVK_F12, 0x58)
        set(kVK_F15, 0x66)
        set(kVK_Help, 0x52, extended: true)
        set(kVK_Home, 0x47, extended: true)
        set(kVK_PageUp, 0x49, extended: true)
        set(kVK_ForwardDelete, 0x53, extended: true)
        set(kVK_F4, 0x3E)
        set(kVK_End, 0x4F, extended: true)
        set(kVK_F2, 0x3C)
        set(kVK_PageDown, 0x51, extended: true)
        set(kVK_F1, 0x3B)
        set(kVK_LeftArrow, 0x4B, extended: true)
        set(kVK_RightArrow, 0x4D, extended: true)
        set(kVK_DownArrow, 0x50, extended: true)
        set(kVK_UpArrow, 0x48, extended: true)
        set(kVK_F17, 0x68)
        set(kVK_F18, 0x69)
        set(kVK_F19, 0x6A)
        set(kVK_F20, 0x6B)

        set(kVK_JIS_Yen, 0x7D)
        set(kVK_JIS_Underscore, 0x73)
        set(kVK_JIS_KeypadComma, 0x7E)
        set(kVK_JIS_Eisu, 0x72)
        set(kVK_JIS_Kana, 0x70)

        return table
    }
}
