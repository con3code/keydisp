import AppKit
import SwiftUI

/// 初回起動時などに表示する、権限設定への誘導画面
struct PermissionGuideView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var inputMonitoringOK = Permissions.inputMonitoringGranted

    var onCompleted: () -> Void
    var onClose: () -> Void

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            Text(L("KeyDisp へようこそ", "Welcome to KeyDisp"))
                .font(.title2.bold())

            Text(L("""
            KeyDisp はキーボード入力を画面に大きく表示するアプリです。
            キー入力を読み取るために、macOS の
            「プライバシーとセキュリティ」で「入力監視」の許可が必要です。
            """, """
            KeyDisp displays your keystrokes on screen.
            To read keyboard input, it needs the Input Monitoring
            permission in macOS Privacy & Security settings.
            """))
            .multilineTextAlignment(.center)
            .foregroundColor(.secondary)
            .font(.system(size: 12.5))
            // これがないと、ウィンドウ側で高さを詰められたときに末尾が「…」で切れる
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                stepRow(
                    number: 1, name: L("入力監視", "Input Monitoring"), granted: inputMonitoringOK,
                    detail: L("システム設定 › プライバシーとセキュリティ › 入力監視 で KeyDisp をオンにしてください。一覧にない場合は「設定を開く」を押すと（オフの状態で）追加されます。",
                              "Turn on KeyDisp in System Settings › Privacy & Security › Input Monitoring. If it is not listed, press \"Open Settings\" to add it (switched off).")
                ) {
                    Permissions.requestInputMonitoring()
                    Permissions.openInputMonitoringSettings()
                }
            }

            HStack(spacing: 10) {
                Text(L("オンにしても［開始］が押せないままの場合は、再起動すると反映されます。",
                       "If Start stays disabled after turning it on, restarting the app applies it."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button(L("アプリを再起動", "Restart App")) { relaunch() }
            }

            HStack {
                Button(L("あとで", "Later")) { onClose() }
                Spacer()
                Button(L("開始", "Start")) { onCompleted() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!inputMonitoringOK)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onReceive(timer) { _ in
            inputMonitoringOK = Permissions.inputMonitoringGranted
            // 許可されたら自動的に閉じてキー表示を始める
            if inputMonitoringOK {
                onCompleted()
            }
        }
    }

    /// 自分自身を再起動する。入力監視の許可は実行中のプロセスへは反映されず、
    /// 再起動して初めて CGPreflightListenEventAccess が true を返すようになるため。
    private func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
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
