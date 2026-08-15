import SwiftUI

/// 初回起動時などに表示する、権限設定への誘導画面
struct PermissionGuideView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var accessibilityOK = Permissions.accessibilityGranted
    @State private var inputMonitoringOK = Permissions.inputMonitoringGranted

    /// 両方の権限が許可されたら自動的に閉じて開始する（初回起動フロー用）。
    /// メニューから意図的に開いた場合は false にして、閉じる操作をユーザーに委ねる。
    var autoCloseWhenGranted: Bool = true
    var onCompleted: () -> Void
    var onClose: () -> Void

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            Text(L("KeyDisp へようこそ", "Welcome to KeyDisp"))
                .font(.title2.bold())

            Text(L("""
            KeyDisp はキーボード入力を画面に大きく表示するアプリです。
            キー入力を読み取るために、macOS の
            「プライバシーとセキュリティ」で以下の許可が必要です。
            """, """
            KeyDisp displays your keystrokes on screen.
            To read keyboard input, it needs the following
            permissions in macOS Privacy & Security settings.
            """))
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)
            .font(.system(size: 12.5))

            VStack(spacing: 10) {
                stepRow(
                    number: 1, name: L("アクセシビリティ", "Accessibility"), granted: accessibilityOK,
                    detail: L("システム設定 › プライバシーとセキュリティ › アクセシビリティ で KeyDisp をオンにしてください。",
                              "Turn on KeyDisp in System Settings › Privacy & Security › Accessibility.")
                ) {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }
                stepRow(
                    number: 2, name: L("入力監視", "Input Monitoring"), granted: inputMonitoringOK,
                    detail: L("システム設定 › プライバシーとセキュリティ › 入力監視 に KeyDisp があればオンにしてください。一覧に表示されない場合もありますが、アクセシビリティが許可されていれば問題ありません。",
                              "Turn on KeyDisp in System Settings › Privacy & Security › Input Monitoring if it is listed. It may not appear in that list at all, which is fine as long as Accessibility is granted.")
                ) {
                    Permissions.requestInputMonitoring()
                    Permissions.openInputMonitoringSettings()
                }
            }

            Text(L("許可を変更した後、アプリの再起動を求められる場合があります。",
                   "macOS may ask you to restart the app after changing permissions."))
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button(L("あとで", "Later")) { onClose() }
                Spacer()
                Button(L("開始", "Start")) { onCompleted() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!(accessibilityOK && inputMonitoringOK))
            }
        }
        .padding(24)
        .frame(width: 440)
        .onReceive(timer) { _ in
            accessibilityOK = Permissions.accessibilityGranted
            inputMonitoringOK = Permissions.inputMonitoringGranted
            if autoCloseWhenGranted && accessibilityOK && inputMonitoringOK {
                onCompleted()
            }
        }
    }

    private func stepRow(
        number: Int, name: String, granted: Bool, detail: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "\(number).circle")
                .font(.system(size: 22))
                .foregroundColor(granted ? .green : .accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted {
                Button(L("設定を開く", "Open Settings")) { action() }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
