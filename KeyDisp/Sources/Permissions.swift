import AppKit
import ApplicationServices

extension Notification.Name {
    /// 権限の再確認とキー監視の再起動を要求する（設定画面 → AppDelegate）
    static let keyDispRecheckPermissions = Notification.Name("KeyDispRecheckPermissions")
}

/// アクセシビリティ / 入力監視の権限まわり
enum Permissions {
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static var inputMonitoringGranted: Bool {
        CGPreflightListenEventAccess()
    }

    static var allGranted: Bool {
        accessibilityGranted && inputMonitoringGranted
    }

    /// システムのプロンプトを表示して権限をリクエストする
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func requestInputMonitoring() {
        CGRequestListenEventAccess()
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
