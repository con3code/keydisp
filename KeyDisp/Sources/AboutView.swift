import SwiftUI

struct AboutView: View {
    @ObservedObject private var settings = AppSettings.shared

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return L("バージョン \(short) (\(build))", "Version \(short) (\(build))")
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("KeyDisp")
                .font(.title.bold())
            Text(version)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(L("押しているキーを画面に大きく表示する\nキーストローク・ビジュアライザ",
                   "A keystroke visualizer that shows\nthe keys you press on screen"))
                .multilineTextAlignment(.center)
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                // これがないと、ウィンドウ側で高さを詰められたときに末尾が「…」で切れる
                .fixedSize(horizontal: false, vertical: true)
            Divider().frame(width: 200)
            Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(28)
        .frame(width: 320)
    }
}
