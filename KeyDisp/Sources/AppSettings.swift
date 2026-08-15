import AppKit
import Combine
import SwiftUI

/// UI の言語
enum AppLanguage: Int, CaseIterable, Identifiable {
    case system = 0
    case japanese = 1
    case english = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .system: return L("システム標準", "System Default")
        case .japanese: return "日本語"
        case .english: return "English"
        }
    }
}

/// 簡易ローカライズ: 現在の言語設定に応じて日本語 / 英語の文言を返す
func L(_ ja: String, _ en: String) -> String {
    AppSettings.shared.isJapanese ? ja : en
}

/// キー表示のデザインスタイル
enum KeyStyle: Int, CaseIterable, Identifiable {
    case simple = 0      // シンプルな文字表示
    case keycap = 1      // キーキャップ風デザイン
    case customImage = 2 // ユーザー指定の背景画像

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .simple: return L("シンプル", "Simple")
        case .keycap: return L("キーキャップ", "Keycap")
        case .customImage: return L("カスタム画像", "Custom Image")
        }
    }
}

/// キー表記の OS スタイル
enum OSLabelStyle: Int, CaseIterable, Identifiable {
    case mac = 0        // ⌘ ⌥ ↩ など macOS の記号
    case windows = 1    // Ctrl Alt Enter など Windows の表記
    case both = 2       // ⌘/Ctrl のような併存表記

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .mac: return "Mac"
        case .windows: return "Windows"
        case .both: return "Mac + Windows"
        }
    }
}

/// アプリ全体の設定。UserDefaults に永続化する。
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let d = UserDefaults.standard

    // MARK: 表示
    @Published var overlayVisible: Bool { didSet { d.set(overlayVisible, forKey: "overlayVisible") } }
    /// 表示サイズ（基準フォントサイズへの倍率）
    @Published var displayScale: Double { didSet { d.set(displayScale, forKey: "displayScale") } }
    /// キーを離してから表示し続ける秒数
    @Published var holdDuration: Double { didSet { d.set(holdDuration, forKey: "holdDuration") } }
    /// フェードアウトにかける秒数
    @Published var fadeDuration: Double { didSet { d.set(fadeDuration, forKey: "fadeDuration") } }
    /// 表示の最大行数
    @Published var maxRows: Double { didSet { d.set(maxRows, forKey: "maxRows") } }
    /// ぶら下がり式（上端基準・新しい行が上、古い行が下に押し下げられる）
    @Published var stackFromTop: Bool { didSet { d.set(stackFromTop, forKey: "stackFromTop") } }
    /// 修飾キーなしの通常タイピング（英数字など）も表示する
    @Published var showAllKeys: Bool { didSet { d.set(showAllKeys, forKey: "showAllKeys") } }
    /// 同じキーの連続押し・長押しリピートを ×n バッジでまとめる
    @Published var countRepeats: Bool { didSet { d.set(countRepeats, forKey: "countRepeats") } }

    // MARK: デザイン
    @Published var style: KeyStyle { didSet { d.set(style.rawValue, forKey: "keyStyle") } }
    @Published var textColorHex: String { didSet { d.set(textColorHex, forKey: "textColorHex") } }
    @Published var keyColorHex: String { didSet { d.set(keyColorHex, forKey: "keyColorHex") } }
    @Published var backgroundOpacity: Double { didSet { d.set(backgroundOpacity, forKey: "backgroundOpacity") } }
    @Published var backgroundEnabled: Bool { didSet { d.set(backgroundEnabled, forKey: "backgroundEnabled") } }
    @Published var customImagePath: String { didSet { d.set(customImagePath, forKey: "customImagePath") } }

    // MARK: キー表記
    /// Mac / Windows / 併存 のキー表記スタイル
    @Published var osLabelStyle: OSLabelStyle { didSet { d.set(osLabelStyle.rawValue, forKey: "osLabelStyle") } }
    /// 英数/かな を ABC/あいう と表示する（新しい JIS 配列の刻印に合わせる）
    @Published var jisABCLabels: Bool { didSet { d.set(jisABCLabels, forKey: "jisABCLabels") } }
    /// キーコンビネーションのキーの間に「+」を表示する（例: Ctrl+Shift+S）
    @Published var plusSeparator: Bool { didSet { d.set(plusSeparator, forKey: "plusSeparator") } }
    /// タイピング表示で英字の大文字/小文字を実際の入力どおりに区別する
    @Published var distinguishCase: Bool { didSet { d.set(distinguishCase, forKey: "distinguishCase") } }
    /// かな入力ユーザー向け: 日本語入力モード中は JIS かな配列のひらがなで表示する
    @Published var kanaDisplay: Bool { didSet { d.set(kanaDisplay, forKey: "kanaDisplay") } }
    /// 入力切替キー（英数/かな・ABC/あいう）に地球儀マークを付ける
    @Published var globeOnImeKeys: Bool { didSet { d.set(globeOnImeKeys, forKey: "globeOnImeKeys") } }

    // MARK: マウス
    /// クリック / ドラッグ中にカーソル位置へ円形ハイライトを表示する
    @Published var mouseHighlight: Bool { didSet { d.set(mouseHighlight, forKey: "mouseHighlight") } }
    @Published var mouseColorHex: String { didSet { d.set(mouseColorHex, forKey: "mouseColorHex") } }
    /// ハイライト円の直径（ポイント）
    @Published var mouseHighlightSize: Double { didSet { d.set(mouseHighlightSize, forKey: "mouseHighlightSize") } }
    /// 修飾キー + クリックをキー表示にも出す（カーソルマークで表示）
    @Published var showClickInKeyDisplay: Bool { didSet { d.set(showClickInKeyDisplay, forKey: "showClickInKeyDisplay") } }
    /// マウスカーソルに追従する大きなポインタを表示する
    @Published var bigCursor: Bool { didSet { d.set(bigCursor, forKey: "bigCursor") } }
    /// 大きなポインタの高さ（ポイント）
    @Published var bigCursorSize: Double { didSet { d.set(bigCursorSize, forKey: "bigCursorSize") } }
    @Published var bigCursorColorHex: String { didSet { d.set(bigCursorColorHex, forKey: "bigCursorColorHex") } }

    // MARK: 一般
    /// UI の言語
    @Published var language: AppLanguage { didSet { d.set(language.rawValue, forKey: "language") } }
    /// 画面の下端にカーソルがある間はキー表示を隠す
    @Published var hotCornerHide: Bool { didSet { d.set(hotCornerHide, forKey: "hotCornerHide") } }
    @Published var showMenuBarIcon: Bool { didSet { d.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    @Published var showDockIcon: Bool { didSet { d.set(showDockIcon, forKey: "showDockIcon") } }
    @Published var launchAtLogin: Bool { didSet { d.set(launchAtLogin, forKey: "launchAtLogin") } }

    // MARK: 表示/非表示ホットキー（Carbon 形式の修飾キーフラグ）
    @Published var hotKeyKeyCode: Int { didSet { d.set(hotKeyKeyCode, forKey: "hotKeyKeyCode") } }
    @Published var hotKeyModifiers: Int { didSet { d.set(hotKeyModifiers, forKey: "hotKeyModifiers") } }

    // MARK: 実行時のみ（永続化しない）
    @Published var editMode: Bool = false
    /// メニューバーホットエッジによる一時非表示中（キー入力の処理も停止する）
    @Published var hotCornerSuppressed: Bool = false

    private init() {
        overlayVisible = d.object(forKey: "overlayVisible") as? Bool ?? true
        displayScale = d.object(forKey: "displayScale") as? Double ?? 1.0
        holdDuration = d.object(forKey: "holdDuration") as? Double ?? 1.5
        fadeDuration = d.object(forKey: "fadeDuration") as? Double ?? 0.8
        maxRows = d.object(forKey: "maxRows") as? Double ?? 4
        stackFromTop = d.object(forKey: "stackFromTop") as? Bool ?? false
        showAllKeys = d.object(forKey: "showAllKeys") as? Bool ?? false
        countRepeats = d.object(forKey: "countRepeats") as? Bool ?? true
        style = KeyStyle(rawValue: d.object(forKey: "keyStyle") as? Int ?? 1) ?? .keycap
        textColorHex = d.object(forKey: "textColorHex") as? String ?? "#FFFFFF"
        keyColorHex = d.object(forKey: "keyColorHex") as? String ?? "#1C1C22"
        backgroundOpacity = d.object(forKey: "backgroundOpacity") as? Double ?? 0.75
        backgroundEnabled = d.object(forKey: "backgroundEnabled") as? Bool ?? true
        customImagePath = d.object(forKey: "customImagePath") as? String ?? ""
        osLabelStyle = OSLabelStyle(rawValue: d.object(forKey: "osLabelStyle") as? Int ?? 0) ?? .mac
        jisABCLabels = d.object(forKey: "jisABCLabels") as? Bool ?? false
        plusSeparator = d.object(forKey: "plusSeparator") as? Bool ?? false
        distinguishCase = d.object(forKey: "distinguishCase") as? Bool ?? false
        kanaDisplay = d.object(forKey: "kanaDisplay") as? Bool ?? false
        globeOnImeKeys = d.object(forKey: "globeOnImeKeys") as? Bool ?? true
        mouseHighlight = d.object(forKey: "mouseHighlight") as? Bool ?? false
        mouseColorHex = d.object(forKey: "mouseColorHex") as? String ?? "#FFB300"
        mouseHighlightSize = d.object(forKey: "mouseHighlightSize") as? Double ?? 56
        showClickInKeyDisplay = d.object(forKey: "showClickInKeyDisplay") as? Bool ?? true
        bigCursor = d.object(forKey: "bigCursor") as? Bool ?? false
        bigCursorSize = d.object(forKey: "bigCursorSize") as? Double ?? 64
        bigCursorColorHex = d.object(forKey: "bigCursorColorHex") as? String ?? "#FFFFFF"
        language = AppLanguage(rawValue: d.object(forKey: "language") as? Int ?? 0) ?? .system
        hotCornerHide = d.object(forKey: "hotCornerHide") as? Bool ?? false
        showMenuBarIcon = d.object(forKey: "showMenuBarIcon") as? Bool ?? true
        showDockIcon = d.object(forKey: "showDockIcon") as? Bool ?? false
        launchAtLogin = d.object(forKey: "launchAtLogin") as? Bool ?? false
        // デフォルト: ⌥⌘K (keycode 40)
        hotKeyKeyCode = d.object(forKey: "hotKeyKeyCode") as? Int ?? 40
        hotKeyModifiers = d.object(forKey: "hotKeyModifiers") as? Int ?? (256 + 2048) // cmdKey + optionKey
    }

    var textColor: NSColor { NSColor(hexString: textColorHex) ?? .white }
    var keyColor: NSColor { NSColor(hexString: keyColorHex) ?? .black }

    /// 現在の言語設定で日本語 UI を使うか
    var isJapanese: Bool {
        switch language {
        case .japanese: return true
        case .english: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
        }
    }
}

// MARK: - 色の hex 変換

extension NSColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if hex.count == 8 {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

extension AppSettings {
    /// SwiftUI の ColorPicker 用バインディングを作る
    func colorBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, String>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hexString: self[keyPath: keyPath]) ?? .white) },
            set: { self[keyPath: keyPath] = NSColor($0).hexString }
        )
    }
}
