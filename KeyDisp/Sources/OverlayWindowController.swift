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
    /// カーソル追従用: 画面ごとの表示設定一式（編集 HUD にある項目）
    private static let profilesByScreenKey = "OverlayProfileByScreen"
    static let defaultSize = NSSize(width: 620, height: 440)

    let panel: NSPanel
    private let model: KeyDisplayModel
    private let settings: AppSettings
    private var cancellables: Set<AnyCancellable> = []
    /// 外側（メニュー・ホットエッジなど）から求められている表示状態
    private var wantsVisible = false
    /// 行が「増えた」ことを検知するための直前の行数（カーソル追従の切替契機）
    private var lastEntryCount = 0
    /// 画面切替でプロファイルを適用している最中（保存の連鎖を防ぐ）
    private var isApplyingProfile = false

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
        restoreHiddenFlagForCurrentScreen()

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
        settings.$hiddenOnCurrentScreen
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshVisibility() }
            .store(in: &cancellables)

        // 編集 HUD にある表示設定（スタイル・サイズ・行数・色・背景など）の変更を、
        // いまキー表示がある画面の設定一式として記憶する
        // （カーソル追従で、会場は大きく濃く・手元は小さく薄く、のような使い分けができるように）
        Publishers.MergeMany(
            settings.$style.map { _ in () }.eraseToAnyPublisher(),
            settings.$displayScale.map { _ in () }.eraseToAnyPublisher(),
            settings.$maxRows.map { _ in () }.eraseToAnyPublisher(),
            settings.$stackFromTop.map { _ in () }.eraseToAnyPublisher(),
            settings.$rowAlignment.map { _ in () }.eraseToAnyPublisher(),
            settings.$textColorHex.map { _ in () }.eraseToAnyPublisher(),
            settings.$keyColorHex.map { _ in () }.eraseToAnyPublisher(),
            settings.$backgroundEnabled.map { _ in () }.eraseToAnyPublisher(),
            settings.$backgroundOpacity.map { _ in () }.eraseToAnyPublisher(),
            settings.$hiddenOnCurrentScreen.map { _ in () }.eraseToAnyPublisher()
        )
        .dropFirst(10)  // 購読時に各設定が 1 回ずつ発火するぶんを読み飛ばす
        .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
        .sink { [weak self] in self?.rememberProfile() }
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
    /// 編集モード中とドラッグ中は動かさない
    private func moveToCursorScreenIfNeeded() {
        guard settings.followCursorScreen, !settings.editMode, dragEndWatcher == nil else { return }
        moveToCursorScreen()
    }

    /// カーソルのある画面へ表示を移す。
    /// その画面で記憶している定位置・表示倍率があれば復元し、無ければ相対位置を比例変換して置く。
    /// 表示編集モードに入るときにも（メニューを操作した画面を編集できるよう）呼ばれる
    func moveToCursorScreen() {
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
        // その画面で記憶している表示設定一式があれば適用する。
        // 必ずフレームを移した後に行う（先に変えると、記憶が移動前の画面に上書きされる）
        if let profile = storedProfile(for: target) {
            applyProfile(profile)
        } else if settings.hiddenOnCurrentScreen {
            // 記憶のない画面は「表示する」が既定
            isApplyingProfile = true
            settings.hiddenOnCurrentScreen = false
            isApplyingProfile = false
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

    /// 編集 HUD にある表示設定の現在値一式
    private func currentProfile() -> [String: Any] {
        [
            "style": settings.style.rawValue,
            "displayScale": settings.displayScale,
            "maxRows": settings.maxRows,
            "stackFromTop": settings.stackFromTop,
            "rowAlignment": settings.rowAlignment.rawValue,
            "textColorHex": settings.textColorHex,
            "keyColorHex": settings.keyColorHex,
            "backgroundEnabled": settings.backgroundEnabled,
            "backgroundOpacity": settings.backgroundOpacity,
            "hidden": settings.hiddenOnCurrentScreen,
        ]
    }

    /// 起動時に、いまキー表示がある画面の「この画面では表示しない」状態を復元する
    private func restoreHiddenFlagForCurrentScreen() {
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let screen = panel.screen ?? screenContaining(center),
              let profile = storedProfile(for: screen) else { return }
        settings.hiddenOnCurrentScreen = (profile["hidden"] as? Bool) ?? false
    }

    /// いまキー表示がある画面の表示設定一式として記憶する
    private func rememberProfile() {
        guard !isApplyingProfile else { return }
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let screen = panel.screen ?? screenContaining(center),
              let key = Self.screenKey(screen) else { return }
        var dict = UserDefaults.standard.dictionary(forKey: Self.profilesByScreenKey) as? [String: [String: Any]] ?? [:]
        dict[key] = currentProfile()
        UserDefaults.standard.set(dict, forKey: Self.profilesByScreenKey)
    }

    private func storedProfile(for screen: NSScreen) -> [String: Any]? {
        guard let key = Self.screenKey(screen),
              let dict = UserDefaults.standard.dictionary(forKey: Self.profilesByScreenKey) as? [String: [String: Any]] else { return nil }
        return dict[key]
    }

    /// 記憶していた表示設定一式を反映する（値が変わるものだけ書き込む）
    private func applyProfile(_ profile: [String: Any]) {
        isApplyingProfile = true
        defer { isApplyingProfile = false }
        if let v = profile["style"] as? Int, let st = KeyStyle(rawValue: v), st != settings.style {
            settings.style = st
        }
        if let v = profile["displayScale"] as? Double, abs(v - settings.displayScale) > 0.001 {
            settings.displayScale = v
        }
        if let v = profile["maxRows"] as? Double, abs(v - settings.maxRows) > 0.001 {
            settings.maxRows = v
        }
        if let v = profile["stackFromTop"] as? Bool, v != settings.stackFromTop {
            settings.stackFromTop = v
        }
        if let v = profile["rowAlignment"] as? Int, let a = RowAlignment(rawValue: v), a != settings.rowAlignment {
            settings.rowAlignment = a
        }
        if let v = profile["textColorHex"] as? String, v != settings.textColorHex {
            settings.textColorHex = v
        }
        if let v = profile["keyColorHex"] as? String, v != settings.keyColorHex {
            settings.keyColorHex = v
        }
        if let v = profile["backgroundEnabled"] as? Bool, v != settings.backgroundEnabled {
            settings.backgroundEnabled = v
        }
        if let v = profile["backgroundOpacity"] as? Double, abs(v - settings.backgroundOpacity) > 0.001 {
            settings.backgroundOpacity = v
        }
        let hidden = (profile["hidden"] as? Bool) ?? false
        if hidden != settings.hiddenOnCurrentScreen {
            settings.hiddenOnCurrentScreen = hidden
        }
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
        // 編集モード中は「この画面では表示しない」でも必ず見せる
        // （見えないまま設定を触ることになり、解除もできなくなるため）
        let shouldShow = settings.editMode
            || (wantsVisible && !model.entries.isEmpty && !settings.hiddenOnCurrentScreen)
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
        // 画面ごとの定位置・表示設定の記憶もすべてクリアして、まっさらな既定状態へ戻す
        UserDefaults.standard.removeObject(forKey: Self.framesByScreenKey)
        UserDefaults.standard.removeObject(forKey: Self.profilesByScreenKey)
        UserDefaults.standard.removeObject(forKey: "OverlayScaleByScreen")  // 旧形式の掃除
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
