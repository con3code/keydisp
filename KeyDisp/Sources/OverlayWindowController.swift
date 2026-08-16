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
    private let model: KeyDisplayModel
    private let settings: AppSettings
    private var cancellables: Set<AnyCancellable> = []
    /// 外側（メニュー・ホットエッジなど）から求められている表示状態
    private var wantsVisible = false

    init(model: KeyDisplayModel, settings: AppSettings = .shared) {
        self.model = model
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
        publishContentWidth()

        // 表示サイズ・行数を変えたときは、キー表示が切れないよう表示領域を広げる
        Publishers.CombineLatest3(
            settings.$displayScale.removeDuplicates(),
            settings.$maxRows.removeDuplicates(),
            settings.$style.removeDuplicates()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.growToFitContent() }
        .store(in: &cancellables)

        // 行がすべて消えたら、透明なウィンドウを画面に載せたままにせず完全に下ろす
        // （描画合成の対象から外れる）。新しい行が入ったら再び載せる
        model.$entries
            .map(\.isEmpty)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshVisibility() }
            .store(in: &cancellables)
        settings.$editMode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshVisibility() }
            .store(in: &cancellables)

        // 「ドラッグで移動」オプションに応じてマウスの受付を切り替える
        settings.$dragToMove
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMouseAcceptance() }
            .store(in: &cancellables)
        refreshMouseAcceptance()

        // 表示部分を掴んだらドラッグ開始とみなし、離すまでフェードを一時停止する。
        // 透明な部分のクリックはウィンドウに届かない（下のアプリへ素通し）ので、
        // このモニタが反応するのは実際に見えているキー表示を掴んだときだけ
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            if let self, event.window === self.panel { self.beginDragFreeze() }
            return event
        }
    }

    /// 通常モードでもドラッグ移動を許可するか（編集モード中は常に許可）
    private func refreshMouseAcceptance() {
        panel.ignoresMouseEvents = !(settings.editMode || settings.dragToMove)
    }

    // MARK: - ドラッグ中のフェード一時停止

    private var dragEndWatcher: Timer?

    /// ドラッグ / リサイズ中は表示を凍結する。
    /// ウィンドウの移動ループは WindowServer 側で進み mouseUp がアプリに
    /// 届かないことがあるため、終了はボタンの実状態を監視して検出する
    private func beginDragFreeze() {
        guard dragEndWatcher == nil else { return }
        model.setFreeze(.dragging, true)
        dragEndWatcher = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            timer.invalidate()
            guard let self else { return }
            self.dragEndWatcher = nil
            self.model.setFreeze(.dragging, false)
        }
    }

    /// 表示すべき内容があるときだけウィンドウを画面に載せる。
    /// 編集モード中はサンプル行を見せるため、空でも必ず載せる
    private func refreshVisibility() {
        let shouldShow = settings.editMode || (wantsVisible && !model.entries.isEmpty)
        if shouldShow {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else {
            if panel.isVisible { panel.orderOut(nil) }
        }
    }

    // MARK: - 表示内容に合わせた拡張

    /// 設定した行数がすべて収まるのに必要な大きさ（内側の余白込み）
    private func requiredSize() -> NSSize {
        let scale = CGFloat(settings.displayScale)
        return NSSize(
            width: max(240, 260 * scale),
            height: OverlayMetrics.requiredHeight(rows: Int(settings.maxRows), settings: settings)
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
        publishContentWidth()
        saveFrame()
    }

    /// 1 行に入るキーの数の判断に使うため、内側の幅を設定へ伝える
    private func publishContentWidth() {
        settings.overlayContentWidth = Double(panel.frame.width - OverlayMetrics.padding)
    }

    func show() {
        wantsVisible = true
        refreshVisibility()
    }

    func hide() {
        wantsVisible = false
        panel.orderOut(nil)
    }

    func setEditMode(_ editing: Bool) {
        refreshMouseAcceptance()
        refreshVisibility()
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

    func windowWillMove(_ notification: Notification) {
        beginDragFreeze()
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        beginDragFreeze()
    }

    func windowDidResize(_ notification: Notification) {
        publishContentWidth()
        saveFrame()
    }
}
