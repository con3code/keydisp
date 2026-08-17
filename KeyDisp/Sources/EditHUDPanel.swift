import AppKit
import SwiftUI

/// 表示編集モードの設定 HUD。
/// オーバーレイとは独立したフローティングパネルなので、
/// オーバーレイが画面いっぱいに広がっても常に画面内で操作できる。
final class EditHUDPanelController: NSObject, NSWindowDelegate {
    private static let autosaveName = "EditHUDPanel"

    let panel: NSPanel
    private let onDone: () -> Void

    init(settings: AppSettings, onDone: @escaping () -> Void) {
        self.onDone = onDone
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        // オーバーレイ (.statusBar) より 1 段高いレベルにして、常に前面に出す。
        // isFloatingPanel はレベルを .floating に上書きするため、必ずその後に設定する。
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self

        let hosting = NSHostingView(rootView: EditHUDView(settings: settings, onDone: onDone))
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.setFrameAutosaveName(Self.autosaveName)
    }

    /// 言語設定に合わせてタイトルを更新する（言語切替え時にも呼ばれる）
    func updateTitle() {
        panel.title = L("表示編集モード", "Edit Display Mode")
    }

    func show() {
        updateTitle()
        // メニューを操作した画面（= カーソルのある画面）に出す。
        // その画面内で以前動かした位置ならそのまま尊重し、
        // 別の画面で開いた場合はその画面の右上に出し直す
        let loc = NSEvent.mouseLocation
        if let target = NSScreen.screens.first(where: { $0.frame.contains(loc) }) ?? NSScreen.main {
            let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
            if !target.frame.contains(center) {
                let v = target.visibleFrame
                panel.setFrameOrigin(NSPoint(
                    x: v.maxX - panel.frame.width - 24,
                    y: v.maxY - panel.frame.height - 24
                ))
            }
        }
        panel.makeKeyAndOrderFront(nil)
        // 開いたままのカラーパネルがあれば、HUD と同じ画面へ連れてくる
        if NSColorPanel.sharedColorPanelExists, NSColorPanel.shared.isVisible {
            ColorPanelScreenFollower.bringToCursorScreen(NSColorPanel.shared)
        }
    }

    func hide() {
        // HUD のカラーピッカーから開いたシステムのカラーパネルを道連れに閉じる。
        // 取り残されると閉じる操作を受け付けないまま画面に残ってしまうため
        if NSColorPanel.sharedColorPanelExists, NSColorPanel.shared.isVisible {
            NSColorPanel.shared.orderOut(nil)
        }
        panel.orderOut(nil)
    }

    /// 閉じるボタン = 編集モード終了
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onDone()
        return false
    }
}

/// HUD の中身。13 インチ画面でも収まるコンパクトな縦型レイアウト。
struct EditHUDView: View {
    @ObservedObject var settings: AppSettings
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("破線の枠の内側をドラッグすると移動、枠の端をドラッグするとリサイズできます。",
                   "Drag inside the dashed frame to move it, or drag its edges to resize."))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(L("この画面ではキー表示を出さない", "Don't show on this screen"),
                   isOn: $settings.hiddenOnCurrentScreen)
                .font(.system(size: 12))
            if settings.hiddenOnCurrentScreen {
                Text(L("編集中はサンプルが見えたままです。完了すると、この画面ではキー表示が出なくなります。",
                       "Samples stay visible while editing. Once you finish, nothing will be shown on this screen."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("", selection: $settings.style) {
                ForEach(KeyStyle.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            sliderRow(L("サイズ", "Size"), value: $settings.displayScale, in: 0.5...5.0)
            sliderRow(L("表示の行数", "Rows"), value: $settings.maxRows, in: 1...8, step: 1)

            Toggle(L("新しい入力を上に表示（ぶら下がり式）", "Newest at top (hang-down)"), isOn: $settings.stackFromTop)
                .font(.system(size: 12))

            HStack(spacing: 16) {
                ColorPicker(L("文字色", "Text"), selection: settings.colorBinding(\.textColorHex))
                ColorPicker(L("背景色", "Key"), selection: settings.colorBinding(\.keyColorHex))
            }
            .font(.system(size: 12))

            Toggle(L("背景を表示", "Show Background"), isOn: $settings.backgroundEnabled)
                .font(.system(size: 12))

            sliderRow(L("背景の濃さ", "Opacity"), value: $settings.backgroundOpacity, in: 0...1)
                .disabled(!settings.backgroundEnabled)

            HStack {
                Spacer()
                Button(L("完了", "Done")) { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func sliderRow(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .frame(width: 70, alignment: .leading)
            if let step {
                Slider(value: value, in: range, step: step)
            } else {
                Slider(value: value, in: range)
            }
        }
    }
}
