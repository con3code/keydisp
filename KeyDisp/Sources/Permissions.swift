import AppKit

extension Notification.Name {
    /// 権限の再確認とキー監視の再起動を要求する（設定画面 → AppDelegate）
    static let keyDispRecheckPermissions = Notification.Name("KeyDispRecheckPermissions")
}

/// 入力監視（Input Monitoring）の権限まわり。
/// サンドボックス（App Store 対応）ではアクセシビリティ権限が使えないため、
/// キー監視は listen-only の CGEventTap + 入力監視の権限だけで行う。
/// Apple DTS もこの組み合わせがサンドボックスで動作することを明言している。
/// （アクセシビリティ基準の旧実装は legacy/developer-id ブランチ）
enum Permissions {
    static var inputMonitoringGranted: Bool {
        CGPreflightListenEventAccess()
    }

    static var allGranted: Bool {
        inputMonitoringGranted
    }

    /// システムのプロンプトを表示して権限をリクエストする。
    /// 一覧から削除された場合でも、再リクエストでシステム設定のリストに再追加される
    static func requestInputMonitoring() {
        CGRequestListenEventAccess()
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
