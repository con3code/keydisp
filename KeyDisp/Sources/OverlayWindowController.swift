import AppKit
import Combine
import SwiftUI

/// キー表示を載せる透明フローティングパネル。
/// 全スペース・フルスクリーン上・セカンドディスプレイでも表示でき、
/// 編集モード中のみマウス操作を受け付ける。
/// 編集モード中は枠の内側ドラッグで移動、枠の端ドラッグで矩形を直接リサイズできる。
final class OverlayWindowController: NSObject, NSWindowDelegate {
    private static let frameKey = "OverlayWindowFrame"
    static let defaultSize = NSSize(width: 620, height: 440)

    let panel: NSPanel
    private let settings: AppSettings
    private var cancellables: Set<AnyCancellable> = []

    init(model: KeyDisplayModel, settings: AppSettings = .shared) {
        self.settings = settings

        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // isFloatingPanel はウィンドウレベルを .floating に上書きするため、必ずその後に設定する
        panel.level = .statusBar
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.contentMinSize = NSSize(width: 240, height: 150)
        panel.delegate = self

        let root = OverlayRootView(model: model, settings: settings)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: Self.defaultSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        restoreFrame()

        // 表示サイズ・行数を変えたときは、キー表示が切れないよう表示領域を広げる
        Publishers.CombineLatest3(
            settings.$displayScale.removeDuplicates(),
            settings.$maxRows.removeDuplicates(),
            settings.$style.removeDuplicates()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.growToFitContent() }
        .store(in: &cancellables)
    }

    // MARK: - 表示内容に合わせた拡張

    /// 現在の表示設定でキー表示 1 行が必要とする高さの目安。
    /// OverlayRootView の文字サイズと上下パディングに、厚み・影のぶんの余裕を足したもの。
    private var rowHeight: CGFloat {
        let scale = CGFloat(settings.displayScale)
        switch settings.style {
        case .keycap:      return 56 * scale  // 文字 30pt + padding 7pt×2 + 厚み
        case .simple:      return 58 * scale  // 文字 34pt + padding 7pt×2
        case .customImage: return 64 * scale  // 文字 34pt + padding 10pt×2
        }
    }

    /// 設定した行数がすべて収まるのに必要な大きさ（内側の余白込み）
    private func requiredSize() -> NSSize {
        let scale = CGFloat(settings.displayScale)
        let rows = CGFloat(max(1, Int(settings.maxRows)))
        let padding: CGFloat = 32
        return NSSize(
            width: max(240, 260 * scale),
            height: rows * rowHeight + (rows - 1) * 8 * scale + padding
        )
    }

    /// 足りない分だけ広げる（利用者が手で広げた大きさは縮めない）。
    /// 表示の基準となる辺（下端揃え／上端揃え）は動かさない。
    private func growToFitContent() {
        let need = requiredSize()
        var frame = panel.frame
        guard frame.width < need.width || frame.height < need.height else { return }

        let newSize = NSSize(
            width: max(frame.width, need.width),
            height: max(frame.height, need.height)
        )
        // 下端基準（積み上げ式）は origin.y を保って上へ、
        // 上端基準（ぶら下がり式）は上端を保って下へ伸ばす
        if settings.stackFromTop {
            frame.origin.y -= newSize.height - frame.height
        }
        frame.size = newSize

        if let screen = panel.screen ?? NSScreen.main {
            let v = screen.visibleFrame
            frame.size.width = min(frame.width, v.width)
            frame.size.height = min(frame.height, v.height)
            frame.origin.x = max(v.minX, min(frame.origin.x, v.maxX - frame.width))
            frame.origin.y = max(v.minY, min(frame.origin.y, v.maxY - frame.height))
        }
        panel.setFrame(frame, display: true)
        saveFrame()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func setEditMode(_ editing: Bool) {
        panel.ignoresMouseEvents = !editing
        if editing {
            panel.orderFrontRegardless()
        }
    }

    /// 位置とサイズをメインスクリーン左下のデフォルト状態へ戻す。
    /// サイズは現在の表示倍率を考慮して決める（大きな倍率でも表示が収まるように）。
    func resetPosition() {
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        let scale = max(1, settings.displayScale)
        var size = NSSize(
            width: Self.defaultSize.width * scale,
            height: Self.defaultSize.height * scale
        )
        size.width = min(size.width, v.width - 80)
        size.height = min(size.height, v.height - 80)
        panel.setFrame(
            NSRect(origin: NSPoint(x: v.minX + 40, y: v.minY + 40), size: size),
            display: true
        )
        saveFrame()
    }

    // MARK: - フレームの保存/復元（マルチディスプレイ対応: 画面外なら戻す）

    private func restoreFrame() {
        if let s = UserDefaults.standard.string(forKey: Self.frameKey) {
            let rect = NSRectFromString(s)
            if !rect.isEmpty, NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) {
                panel.setFrame(rect, display: false)
                return
            }
        }
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.minX + 40, y: f.minY + 40))
        }
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame()
    }
}
