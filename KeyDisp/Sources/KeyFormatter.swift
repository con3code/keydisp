import Carbon
import CoreGraphics
import Foundation

/// キーコード・修飾キーを表示用文字列に変換する
enum KeyFormatter {

    /// 特殊キーの表示記号
    private static let specialKeys: [CGKeyCode: String] = [
        36: "↩",    // Return
        48: "⇥",    // Tab
        49: "␣",    // Space
        51: "⌫",    // Delete (Backspace)
        53: "⎋",    // Escape
        57: "⇪",    // Caps Lock
        76: "⌤",    // Keypad Enter
        102: "英数", // JIS Eisu
        104: "かな", // JIS Kana
        105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        114: "?⃝",   // Help
        115: "↖",   // Home
        116: "⇞",   // Page Up
        117: "⌦",   // Forward Delete
        119: "↘",   // End
        121: "⇟",   // Page Down
        122: "F1", 120: "F2", 99: "F3", 118: "F4",
        96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        // fn なしで押したときの機能キー（輝度・Mission Control など）は
        // 専用のキーコードで届くため、物理キーの F 番号へ対応付ける
        145: "F1",  // 輝度を下げる
        144: "F2",  // 輝度を上げる
        160: "F3",  // Mission Control
        131: "F4",  // Launchpad
        130: "F4",  // Dashboard（旧機種）
        177: "F4",  // Spotlight（新機種）
        176: "F5",  // 音声入力
        178: "F6",  // おやすみモード
    ]

    /// fn フラグが暗黙に付くキー（矢印・ファンクションキーなど）。
    /// これらのキーでは fn 表示を省略する。
    private static let implicitFnKeys: Set<CGKeyCode> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        105, 107, 113, 106, 64, 79, 80, 90,
        123, 124, 125, 126, 115, 116, 117, 119, 121, 114,
        130, 131, 144, 145, 160, 176, 177, 178,
    ]

    /// 修飾キー自体のキーコード
    static let modifierKeyCodes: Set<CGKeyCode> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    /// Mac 記号 → Windows 表記の対応表（ショートカット互換の対応付け）
    private static let windowsLabels: [String: String] = [
        "⌃": "Ctrl", "⌥": "Alt", "⇧": "Shift", "⌘": "Ctrl", "fn": "Fn",
        "↩": "Enter", "⌤": "Enter", "⇥": "Tab", "␣": "Space",
        "⌫": "BackSpace", "⌦": "Delete", "⎋": "Esc", "⇪": "CapsLock",
        "↖": "Home", "↘": "End", "⇞": "PgUp", "⇟": "PgDn",
        "英数": "無変換", "かな": "変換",
    ]

    /// 表記設定（ABC/あいう、Mac/Windows/併存）を 1 トークンへ適用する
    static func localized(_ token: String) -> String {
        let settings = AppSettings.shared
        var mac = token
        if settings.jisABCLabels {
            if token == "英数" { mac = "ABC" }
            if token == "かな" { mac = "あいう" }
        }
        switch settings.osLabelStyle {
        case .mac:
            return mac
        case .windows:
            return windowsLabels[token] ?? mac
        case .both:
            if let win = windowsLabels[token], win != mac {
                return "\(mac)/\(win)"
            }
            return mac
        }
    }

    /// 修飾キーの記号列（macOS の標準的な表記順: ⌃⌥⇧⌘）
    static func modifierTokens(_ flags: CGEventFlags, keyCode: CGKeyCode? = nil) -> [String] {
        var tokens: [String] = []
        if flags.contains(.maskSecondaryFn) {
            if keyCode == nil || !implicitFnKeys.contains(keyCode!) {
                tokens.append("fn")
            }
        }
        if flags.contains(.maskControl) { tokens.append("⌃") }
        if flags.contains(.maskAlternate) { tokens.append("⌥") }
        if flags.contains(.maskShift) { tokens.append("⇧") }
        if flags.contains(.maskCommand) { tokens.append("⌘") }
        // Windows 表記では ⌃ と ⌘ がどちらも Ctrl になるため、重複を除く
        let mapped = tokens.map(localized)
        var seen = Set<String>()
        return mapped.filter { seen.insert($0).inserted }
    }

    /// 表示に関係する修飾フラグだけを取り出す
    static func relevantFlags(_ flags: CGEventFlags) -> CGEventFlags {
        var out = CGEventFlags()
        for f in [CGEventFlags.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn] {
            if flags.contains(f) { out.insert(f) }
        }
        return out
    }

    /// 印字可能な文字キーかどうか（特殊キー・修飾キーでない）
    static func isCharacterKey(_ code: CGKeyCode) -> Bool {
        specialKeys[code] == nil && !modifierKeyCodes.contains(code)
    }

    /// キーコードを表示文字列へ変換
    /// - Parameters:
    ///   - applyLabelStyle: 表記設定（ABC/あいう、Windows 表記）を適用するか。
    ///     アプリ内 UI（ショートカット表示など）では false にして Mac 記号のまま使う。
    ///   - preserveCase: true なら実際の入力どおりの大文字/小文字で返す
    ///     （タイピング表示専用。コンビネーションは常に大文字表記）。
    static func keyLabel(
        _ code: CGKeyCode, shifted: Bool = false, capsLock: Bool = false,
        applyLabelStyle: Bool = true, preserveCase: Bool = false
    ) -> String {
        if let s = specialKeys[code] { return applyLabelStyle ? localized(s) : s }
        if let c = character(for: code, shifted: shifted, capsLock: capsLock), !c.isEmpty {
            if preserveCase { return c }
            return c.count == 1 ? c.uppercased() : c
        }
        return "key\(code)"
    }

    /// 現在のキーボードレイアウトで文字に変換する
    private static func character(for code: CGKeyCode, shifted: Bool, capsLock: Bool = false) -> String? {
        guard let layoutData = currentLayoutData() else { return nil }
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 8)
        var length = 0
        // Carbon の shiftKey (0x0200) / alphaLock (0x0400) を 8bit 右シフトした形式で渡す
        var modifierKeyState: UInt32 = 0
        if shifted { modifierKeyState |= UInt32((shiftKey >> 8) & 0xFF) }
        if capsLock { modifierKeyState |= UInt32((alphaLock >> 8) & 0xFF) }
        let status = layoutData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> OSStatus in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(
                base, code, UInt16(kUCKeyActionDisplay), modifierKeyState,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState, chars.count, &length, &chars
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    private static func currentLayoutData() -> Data? {
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            return Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        }
        // 日本語入力ソースなどでレイアウトデータが取れない場合は ASCII レイアウトへフォールバック
        if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            return Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        }
        return nil
    }

    // MARK: - JIS かな配列表示用

    /// JIS かな配列: キーコード → (通常, Shift 押下時)
    private static let jisKana: [CGKeyCode: (normal: String, shifted: String?)] = [
        // 数字列
        18: ("ぬ", nil), 19: ("ふ", nil), 20: ("あ", "ぁ"), 21: ("う", "ぅ"),
        23: ("え", "ぇ"), 22: ("お", "ぉ"), 26: ("や", "ゃ"), 28: ("ゆ", "ゅ"),
        25: ("よ", "ょ"), 29: ("わ", "を"), 27: ("ほ", nil), 24: ("へ", nil), 93: ("ー", nil),
        // 上段
        12: ("た", nil), 13: ("て", nil), 14: ("い", "ぃ"), 15: ("す", nil),
        17: ("か", nil), 16: ("ん", nil), 32: ("な", nil), 34: ("に", nil),
        31: ("ら", nil), 35: ("せ", nil), 33: ("゛", nil), 30: ("゜", "「"),
        // 中段
        // 注意: キーコードは A=0, S=1, D=2, F=3, H=4, G=5 の順（G と H が逆順）
        0: ("ち", nil), 1: ("と", nil), 2: ("し", nil), 3: ("は", nil),
        5: ("き", nil), 4: ("く", nil), 38: ("ま", nil), 40: ("の", nil),
        37: ("り", nil), 41: ("れ", nil), 39: ("け", nil), 42: ("む", "」"),
        // 下段
        6: ("つ", "っ"), 7: ("さ", nil), 8: ("そ", nil), 9: ("ひ", nil),
        11: ("こ", nil), 45: ("み", nil), 46: ("も", nil), 43: ("ね", "、"),
        47: ("る", "。"), 44: ("め", "・"), 94: ("ろ", nil),
    ]

    /// JIS かな配列でのラベル（対応するキーでなければ nil）
    static func kanaLabel(_ code: CGKeyCode, shifted: Bool) -> String? {
        guard let entry = jisKana[code] else { return nil }
        return shifted ? (entry.shifted ?? entry.normal) : entry.normal
    }

    /// 現在の入力ソースが日本語入力モード（かな）かどうか
    static func isJapaneseInputMode() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyInputModeID) else { return false }
        let mode = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        return mode.contains("Japanese") && !mode.contains("Roman")
    }

    // MARK: - 入力切替キー表示用

    /// 入力切替キー（英数/かな・ABC/あいう、併存表記含む）のトークンかどうか。
    /// タイピングのトークンは 1 文字なので、これらの複数文字トークンと衝突しない。
    static func isImeSwitchToken(_ token: String) -> Bool {
        ["英数", "かな", "ABC", "あいう"].contains { token == $0 || token.hasPrefix($0 + "/") }
    }

    // MARK: - マウスクリック表示用

    /// クリックを表す内部トークン（描画時に SF Symbols のカーソル画像へ置き換える）
    static func clickToken(button: Int) -> String {
        switch button {
        case 0: return "«click»"
        case 1: return "«rclick»"
        default: return "«mclick»"
        }
    }

    /// クリックトークンなら対応する SF Symbols 名を返す
    static func clickSymbolName(for token: String) -> String? {
        switch token {
        case "«click»": return "cursorarrow"           // 左クリック: カーソル矢印
        case "«rclick»": return "cursorarrow.click.2"  // 右クリック
        case "«mclick»": return "cursorarrow.click"    // 中ボタン
        default: return nil
        }
    }

    // MARK: - ホットキー表示用

    /// Carbon 修飾フラグ + キーコードを「⌥⌘K」のような文字列にする
    static func shortcutDescription(keyCode: Int, carbonModifiers: Int) -> String {
        var s = ""
        if carbonModifiers & controlKey != 0 { s += "⌃" }
        if carbonModifiers & optionKey != 0 { s += "⌥" }
        if carbonModifiers & shiftKey != 0 { s += "⇧" }
        if carbonModifiers & cmdKey != 0 { s += "⌘" }
        s += keyLabel(CGKeyCode(keyCode), applyLabelStyle: false)
        return s
    }
}
