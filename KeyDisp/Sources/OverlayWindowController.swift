import AppKit
import Combine
import SwiftUI

/// キー表示を載せる透明フローティングパネル。
/// 全スペース・フルスクリーン上・セカンドディスプレイでも表示でき、
/// 編集モード中のみマウス操作を受け付ける。
/// 編集モード中は枠の内側ドラッグで移動、枠の端ドラッグで矩形を直接リサイズできる。
final class OverlayWindowController: NSObject, NSWindowDelegate {
    private static let frameKey = "OverlayWindowFrame"
    /// カーソル追従用: 画面（ディスプレイ UUID）ごとの定位置
    private static let framesByScreenKey = "OverlayFrameByScreen"
    /// カーソル追従用: 画面ごとの表示倍率（キーの大きさ）
    private static let scalesByScreenKey = "OverlayScaleByScreen"
    static let defaultSize = NSSize(width: 620, height: 440)

    let panel: NSPanel
    private let model: KeyDisplayModel
    private let settings: AppSettings
    private var cancellables: Set<AnyCancellable> = []
    /// 外側（メニュー・ホットエッジなど）から求められている表示状態
    private var wantsVisible = false
    /// 行が「増えた」ことを検知するための直前の行数（カーソル追従の切替契機）
    private var lastEntryCount = 0

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
        // （描画合成の対象から外れる）。新しい行が入ったら再び載せる。
        // カーソル追従はタイマーで追わず、行が増えるこのタイミングに便乗する
        model.$entries
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in
                guard let self else { return }
                let added = entries.count > self.lastEntryCount
                self.lastEntryCount = entries.count
                if added { self.moveToCursorScreenIfNeeded() }
                self.refreshVisibility()
            }
            .store(in: &cancellables)
        settings.$editMode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshVisibility() }
            .store(in: &cancellables)

        // 表示倍率（サイズ）の変更を、いまいる画面の値として記憶する
        // （カーソル追従で、会場は大きく・手元は小さく、のような使い分けができるように）
        settings.$displayScale
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scale in self?.rememberScale(scale) }
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

    // MARK: - カーソルのある画面への追従

    /// カーソルのある画面へ表示を移す（オプションがオンのとき）。
    /// その画面で記憶している定位置があればそこへ、無ければ相対位置を比例変換して置く。
    /// 編集モード中とドラッグ中は動かさない
    private func moveToCursorScreenIfNeeded() {
        guard settings.followCursorScreen, !settings.editMode, dragEndWatcher == nil else { return }
        let loc = NSEvent.mouseLocation
        guard let target = NSScreen.screens.first(where: { $0.frame.contains(loc) }) else { return }
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        if target.frame.contains(center) { return }  // すでにその画面にいる

        let frame = storedFrame(for: target) ?? Self.remap(
            panel.frame,
            from: (screenContaining(center) ?? target).visibleFrame,
            to: target.visibleFrame
        )
        panel.setFrame(clamp(frame, to: target), display: true)
        publishContentWidth()
        saveFrame()
        // その画面で記憶している表示倍率があれば切り替える。
        // 必ずフレームを移した後に行う（先に変えると、倍率の記憶が移動前の画面に上書きされる）
        if let scale = storedScale(for: target), abs(scale - settings.displayScale) > 0.001 {
            settings.displayScale = scale
        }
    }

    /// その画面で記憶している定位置（画面内に収まっているもののみ）
    private func storedFrame(for screen: NSScreen) -> NSRect? {
        guard let key = Self.screenKey(screen),
              let dict = UserDefaults.standard.dictionary(forKey: Self.framesByScreenKey) as? [String: String],
              let str = dict[key] else { return nil }
        let rect = NSRectFromString(str)
        guard !rect.isEmpty, screen.frame.intersects(rect) else { return nil }
        return rect
    }

    /// 元の画面内での相対位置（余白に対する比率）を保ったまま、別の画面へ写像する
    static func remap(_ frame: NSRect, from source: NSRect, to target: NSRect) -> NSRect {
        var f = frame
        let rx = source.width > frame.width
            ? (frame.minX - source.minX) / (source.width - frame.width) : 0
        let ry = source.height > frame.height
            ? (frame.minY - source.minY) / (source.height - frame.height) : 0
        f.origin.x = target.minX + max(0, min(1, rx)) * max(0, target.width - frame.width)
        f.origin.y = target.minY + max(0, min(1, ry)) * max(0, target.height - frame.height)
        return f
    }

    private func clamp(_ frame: NSRect, to screen: NSScreen) -> NSRect {
        var f = frame
        let v = screen.visibleFrame
        f.size.width = min(f.width, v.width)
        f.size.height = min(f.height, v.height)
        f.origin.x = max(v.minX, min(f.origin.x, v.maxX - f.width))
        f.origin.y = max(v.minY, min(f.origin.y, v.maxY - f.height))
        return f
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    /// いまキー表示がある画面の表示倍率として記憶する
    private func rememberScale(_ scale: Double) {
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let screen = panel.screen ?? screenContaining(center),
              let key = Self.screenKey(screen) else { return }
        var dict = UserDefaults.standard.dictionary(forKey: Self.scalesByScreenKey) as? [String: Double] ?? [:]
        dict[key] = scale
        UserDefaults.standard.set(dict, forKey: Self.scalesByScreenKey)
    }

    private func storedScale(for screen: NSScreen) -> Double? {
        guard let key = Self.screenKey(screen),
              let dict = UserDefaults.standard.dictionary(forKey: Self.scalesByScreenKey) as? [String: Double] else { return nil }
        return dict[key]
    }

    /// ディスプレイ固有の識別子。プロジェクタを抜き差ししても記憶が残るよう UUID を使う
    private static func screenKey(_ screen: NSScreen) -> String? {
        guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(num)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
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
        // 画面ごとの定位置・表示倍率の記憶もすべてクリアして、まっさらな既定状態へ戻す
        UserDefaults.standard.removeObject(forKey: Self.framesByScreenKey)
        UserDefaults.standard.removeObject(forKey: Self.scalesByScreenKey)
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
        // いまいる画面の定位置としても記憶する（カーソル追従で戻ってきたときに使う）
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        if let screen = panel.screen ?? screenContaining(center), let key = Self.screenKey(screen) {
            var dict = UserDefaults.standard.dictionary(forKey: Self.framesByScreenKey) as? [String: String] ?? [:]
            dict[key] = NSStringFromRect(panel.frame)
            UserDefaults.standard.set(dict, forKey: Self.framesByScreenKey)
        }
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
