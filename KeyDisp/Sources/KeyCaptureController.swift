import AppKit
import CoreGraphics

/// CGEventTap でキーボードイベントを監視し、KeyDisplayModel へ流し込む
final class KeyCaptureController {
    private let model: KeyDisplayModel
    private let settings: AppSettings

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// 表示と実際の入力状態を定期的に突き合わせるタイマー
    private var reconcileTimer: Timer?

    // 状態
    private var pressedKeys: Set<CGKeyCode> = []
    private var currentID: UUID?
    private var currentIsModifierOnly = false
    private var currentModifiers: CGEventFlags = []
    /// 修飾キー単独行に表示する内容。一連の操作で押された修飾キーの最大集合を保つ。
    /// （⌘⇧ を押して片方を先に離しても、表示は「⇧⌘」のまま残す）
    private var modifierPeak: CGEventFlags = []
    /// 修飾キーが減ったときの処理を、押し続けるか確かめるまで保留しておくもの
    private var modifierShrinkWork: DispatchWorkItem?
    /// 修飾キーを押した順（押下順表示オプション用）
    private var modifierPressOrder: [CGEventFlags] = []
    /// この時間だけ押し続けたら「意図して押している」とみなす。
    /// これより早く離した場合は 1 回の操作の一部として扱う（設定で変更可）。
    private var deliberateHoldDelay: TimeInterval { settings.holdJudgeDelay }
    /// コンボのキーを離した後、修飾キーだけが残っている間は
    /// 修飾キー単独行を出さないためのフラグ
    private var suppressModifierEntry = false
    /// 修飾キー + クリックの表示行
    private var mouseEntryID: UUID?
    /// 直前のコンビネーション行（同じキーの連続押しを ×n にまとめる判定用）
    private var lastComboID: UUID?
    private var lastComboTokens: [String]?
    /// 直前の矢印キー行（連続入力をまとめる判定用）
    private var lastArrowID: UUID?
    private var lastArrowTime: TimeInterval = 0
    /// タイピング（修飾なし文字入力)の連結用
    private var lastTypingID: UUID?
    private var lastTypingTime: TimeInterval = 0
    private let typingAppendWindow: TimeInterval = 1.2
    /// 連結の上限（暴走を防ぐための安全弁）
    private let maxTypingTokens = 400

    /// タイピング行にもう 1 文字入るか。
    /// キーキャップ・カスタム画像はキーが 1 つずつ独立して並ぶので、端まで来たら
    /// 折り返さずに行を改めて先頭から続ける（タイプライター式）。
    /// 端の判定は実際の文字幅を測って行う（文字数の目安だと判定が甘くなり、
    /// 行の中で折り返しが起きた後に遅れて区切られてしまう）。
    /// シンプル表示は文字が流れる方が自然なので、従来どおり折り返しに任せる。
    private func typingRowHasRoom(id: UUID, adding token: String) -> Bool {
        guard let tokens = model.entries.first(where: { $0.id == id })?.tokens else { return false }
        guard tokens.count < maxTypingTokens else { return false }
        guard OverlayMetrics.usesTypewriterWrap(settings) else { return true }
        let width = CGFloat(settings.overlayContentWidth)
        guard width > 0 else { return true }
        return OverlayMetrics.typingLineFits(tokens + [token], width: width, settings: settings)
    }

    private(set) var isRunning = false

    /// マウスイベントの転送先（type, buttonNumber）。メインスレッドで呼ばれる。
    var onMouseEvent: ((CGEventType, Int) -> Void)?
    /// カーソルが動いたときの通知（大きいカーソルの追従用）
    var onMouseMoved: (() -> Void)?

    init(model: KeyDisplayModel, settings: AppSettings = .shared) {
        self.model = model
        self.settings = settings
    }

    /// イベントタップを開始。権限が無い場合は false。
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)
        // .mouseMoved は購読しない。タップに含めるとマウスを動かすたびに
        // このプロセスが起床してしまうため、必要とする側（大きいカーソル）が
        // 機能オンの間だけ NSEvent のモニタで受ける。

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            if let userInfo {
                let controller = Unmanaged<KeyCaptureController>.fromOpaque(userInfo).takeUnretainedValue()
                controller.handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // 入力が止まった後でも取り残しが残らないよう、定期的に実際の状態と突き合わせる
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.reconcileHeldState()
        }

        isRunning = true
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        reconcileTimer?.invalidate()
        reconcileTimer = nil
        tap = nil
        runLoopSource = nil
        isRunning = false
        resetState()
    }

    private func resetState() {
        pressedKeys.removeAll()
        currentID = nil
        currentIsModifierOnly = false
        currentModifiers = []
        modifierPeak = []
        modifierPressOrder = []
        cancelModifierShrink()
        suppressModifierEntry = false
        lastTypingID = nil
        mouseEntryID = nil
        lastComboID = nil
        lastComboTokens = nil
        lastArrowID = nil
    }

    // MARK: - 修飾キーが減ったときの保留処理

    private func cancelModifierShrink() {
        modifierShrinkWork?.cancel()
        modifierShrinkWork = nil
    }

    /// いま実際に押されているキーだけでトークン列を作る。
    /// 修飾キーも、英数・かな・Tab のような通常のキーも同じように扱う。
    private func heldTokens() -> [String] {
        var tokens = KeyFormatter.modifierTokens(currentModifiers, pressOrder: modifierPressOrder)
        for code in pressedKeys.sorted() where !KeyFormatter.modifierKeyCodes.contains(code) {
            tokens.append(KeyFormatter.keyLabel(code, shifted: false))
        }
        return tokens
    }

    /// 押していたキーの一部を離した後、`deliberateHoldDelay` だけ残りを押し続けたときの処理を予約する。
    /// - 「離すたびに履歴を残す」オン: そこまでの組み合わせを履歴として確定し、残りを新しい行にする
    /// - オフ: 行は増やさず、同じ行を残りのキーだけの表示へ狭める
    ///
    /// どちらも、それより早く離しきった場合は取り消され、押した組み合わせ全体が 1 行として残る。
    private func armRowNarrow() {
        cancelModifierShrink()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  let id = self.currentID,
                  self.entryCount(id) == 1 else { return }
            let tokens = self.heldTokens()
            guard !tokens.isEmpty else { return }
            if self.settings.stepModifierRelease {
                self.model.release(id: id)
                self.lastComboID = id
                self.lastComboTokens = self.model.entries.first(where: { $0.id == id })?.tokens
                self.currentID = self.model.begin(tokens: tokens, isTyping: false)
            } else {
                self.model.update(id: id, tokens: tokens, isTyping: false)
            }
            self.modifierPeak = self.currentModifiers
            // 通常のキーが残っていなければ、以後は修飾キー単独行として扱う
            self.currentIsModifierOnly = !self.pressedKeys.contains {
                !KeyFormatter.modifierKeyCodes.contains($0)
            }
            self.modifierShrinkWork = nil
        }
        modifierShrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + deliberateHoldDelay, execute: work)
    }

    // MARK: - 矢印キーのまとめ

    /// 矢印キーを 1 行にまとめる。まとめた場合は true（呼び出し側は通常処理を行わない）。
    /// - 同時押しのみ: いま他の矢印キーも押されているときだけ 1 行にまとめる（→↓ の斜め移動）
    /// - 連続入力もまとめる: 続けて押した矢印も同じ行へ足していく（→→↓）
    private func handleArrowGrouping(code: CGKeyCode, flags: CGEventFlags, now: TimeInterval) -> Bool {
        guard settings.arrowGrouping != .off,
              KeyFormatter.arrowKeyCodes.contains(code),
              // 修飾キーとの組み合わせは従来どおりコンビネーションとして扱う
              KeyFormatter.relevantFlags(flags).subtracting(.maskSecondaryFn).isEmpty
        else { return false }

        let token = KeyFormatter.keyLabel(code, shifted: false)
        let otherArrowHeld = pressedKeys.contains {
            $0 != code && KeyFormatter.arrowKeyCodes.contains($0)
        }
        let withinWindow = now - lastArrowTime < typingAppendWindow
        let canJoin: Bool
        switch settings.arrowGrouping {
        case .simultaneous: canJoin = otherArrowHeld
        case .consecutive:  canJoin = otherArrowHeld || withinWindow
        case .off:          canJoin = false
        }

        if canJoin, let id = lastArrowID, model.phase(of: id) != nil {
            if entryCount(id) > 1 {
                // ×n になった行へ別の矢印を足すと「→ ×4」が「→↓ ×4」に化けてしまう。
                // この押下で加算した 1 回ぶんを差し戻して履歴に残し、
                // いま押している組み合わせは新しい行にする（コンボと同じ扱い）
                model.decrement(id: id)
                model.release(id: id)
                let tokens = (model.entries.first(where: { $0.id == id })?.tokens ?? []) + [token]
                let newID = model.begin(tokens: tokens, isTyping: false)
                currentID = newID
                currentIsModifierOnly = false
                lastArrowID = newID
                lastArrowTime = now
                lastTypingID = nil
                lastComboID = newID
                lastComboTokens = tokens
                return true
            }
            if model.append(id: id, token: token) {
                currentID = id
                currentIsModifierOnly = false
                lastArrowTime = now
                // 行の中身が変わったので、×n のまとめ先の照合にも増えた後の並びを使う
                lastComboID = id
                lastComboTokens = model.entries.first(where: { $0.id == id })?.tokens ?? []
                return true
            }
        }

        // 同じ矢印だけを続けて押した場合（同時押しでまとめられなかった場合）は、
        // 他のキーと同じく「同じキーの連続入力を ×n でまとめる」の設定に従う
        if let target = mergeTargetID(for: [token]) {
            if let id = currentID, id != target { model.release(id: id) }
            model.increment(id: target)
            currentID = target
            currentIsModifierOnly = false
            lastArrowID = target
            lastArrowTime = now
            lastTypingID = nil
            return true
        }

        if let id = currentID { model.release(id: id) }
        let id = model.begin(tokens: [token], isTyping: false)
        currentID = id
        currentIsModifierOnly = false
        lastArrowID = id
        lastArrowTime = now
        lastTypingID = nil
        lastComboID = id
        lastComboTokens = [token]
        return true
    }

    /// 直前に残った「fn」単独の行を取り除く（🌐 キーの二重表示防止）。
    /// fn を修飾キーとして使った行（fn+← など）は単独行ではないので影響しない
    private func removeTrailingLoneFnRow() {
        let fnLabel = KeyFormatter.localized("fn")
        guard let last = model.entries.last, !last.isTyping, last.tokens == [fnLabel] else { return }
        if currentID == last.id {
            currentID = nil
            currentIsModifierOnly = false
        }
        model.remove(id: last.id)
        // fn 行は無かったことにするので、連打まとめ（×n）の照合先も
        // 1 つ前の行へ戻す（🌐 連打が 1 行にまとまるように）
        if let prev = model.entries.last, !prev.isTyping {
            lastComboID = prev.id
            lastComboTokens = prev.tokens
        } else {
            lastComboID = nil
            lastComboTokens = nil
        }
    }

    // MARK: - 取り残された表示の回収

    /// いま「押されている」として扱っている行。これ以外に押しっぱなしの行があってはならない。
    private var liveRowIDs: Set<UUID> {
        Set([currentID, mouseEntryID].compactMap { $0 })
    }

    /// コントローラが管理していない押しっぱなしの行を解放する。
    /// 何らかの理由で取り残された行は、ここで必ず通常のフェードに乗る。
    private func releaseOrphanRows() {
        let live = liveRowIDs
        for entry in model.entries where entry.phase == .active && !live.contains(entry.id) {
            model.release(id: entry.id)
        }
    }

    /// 実際のキーボード・マウスの状態と突き合わせて、表示のつじつまを合わせる。
    /// イベントを取りこぼしても（別アプリへの切替えなどで keyUp が届かない場合など）、
    /// ここで必ず現実に追いつく。定期実行とイベント処理の両方から呼ばれる。
    func reconcileHeldState() {
        // 実際には離されているキーが押下中のまま残っていたら取り除く
        for code in pressedKeys where !CGEventSource.keyState(.combinedSessionState, key: code) {
            pressedKeys.remove(code)
        }
        let realFlags = KeyFormatter.relevantFlags(
            CGEventSource.flagsState(.combinedSessionState)
        )
        if pressedKeys.isEmpty, realFlags.isEmpty, mouseEntryID == nil, let id = currentID {
            // 物理的には何も押していないのに押しっぱなし扱いの行が残っている
            model.release(id: id)
            currentID = nil
            currentIsModifierOnly = false
            modifierPeak = []
        }
        releaseOrphanRows()
    }

    /// エントリの現在の連続カウント（存在しなければ 1）
    private func entryCount(_ id: UUID) -> Int {
        model.entries.first(where: { $0.id == id })?.count ?? 1
    }

    /// 直前のコンビネーション行がまだ最後の行として生きていれば、その ID を返す（連続押しマージ用）
    private func mergeTargetID(for tokens: [String], ignoring: UUID? = nil) -> UUID? {
        guard settings.countRepeats,
              tokens == lastComboTokens,
              let lid = lastComboID,
              model.phase(of: lid) != nil else { return nil }
        // 間に別の行が挟まった場合はマージしない（連続した入力のみまとめる)
        let visible = model.entries.filter { $0.id != ignoring }
        guard visible.last?.id == lid else { return nil }
        return lid
    }

    // MARK: - イベント処理

    /// イベントの入口。イベントタップから呼ばれるほか、テストからも直接呼べる。
    func handle(type: CGEventType, event: CGEvent) {
        // タイムアウト等でタップが無効化されたら再度有効にする
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        // マウスイベントはキー表示の表示/非表示とは独立して転送する
        switch type {
        case .leftMouseDown, .leftMouseUp,
             .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            onMouseMoved?()
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            onMouseEvent?(type, button)
            handleMouseForDisplay(type: type, event: event, button: button)
            releaseOrphanRows()
            return
        default:
            break
        }

        // 非表示中（設定オフ or ホットエッジによる一時非表示）はキー入力を処理しない
        guard settings.overlayVisible, !settings.hotCornerSuppressed else {
            if !pressedKeys.isEmpty || currentID != nil { resetState() }
            return
        }

        switch type {
        case .keyDown: handleKeyDown(event)
        case .keyUp: handleKeyUp(event)
        case .flagsChanged: handleFlagsChanged(event)
        default: break
        }

        // 取り残された行があればここで回収する（複雑な組み合わせの取りこぼし対策）
        releaseOrphanRows()
    }

    private func handleKeyDown(_ event: CGEvent) {
        let code = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))

        // 長押しの autorepeat は、コンビネーション/特殊キー行のカウントとして数える。
        // ただし入力切替キーは何回リピートしてもモードが変わらないので数えない。
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            if settings.countRepeats, let id = currentID, !currentIsModifierOnly,
               !KeyFormatter.noRepeatKeyCodes.contains(code),
               model.entries.first(where: { $0.id == id })?.isTyping == false {
                model.increment(id: id)
            }
            return
        }
        pressedKeys.insert(code)
        // 文字キーが押されたなら修飾キー行はコンビネーションへ変わるので、保留中の処理は破棄する
        cancelModifierShrink()

        let flags = KeyFormatter.relevantFlags(event.flags)
        // 矢印やファンクションキーには fn が暗黙に付くので、押している修飾キーとしては数えない。
        // ただし fn を実際に押している（先に flagsChanged で届いている）場合はそのまま残す。
        var held = flags
        if !currentModifiers.contains(.maskSecondaryFn), KeyFormatter.hasImplicitFn(code) {
            held.remove(.maskSecondaryFn)
        }
        currentModifiers = held
        let shiftOnly = flags == .maskShift
        let isChar = KeyFormatter.isCharacterKey(code)
        let now = ProcessInfo.processInfo.systemUptime

        // 文章を打っている途中のスペースは、区切らずタイピングの一部として扱う。
        // 単独で押した場合（連結が切れているとき）は従来どおり特殊キーとして表示する。
        let typingIsLive = lastTypingID.map { id in
            now - lastTypingTime < typingAppendWindow && model.phase(of: id) != nil
        } ?? false
        let spaceInTyping = code == 49 && (flags.isEmpty || shiftOnly) && typingIsLive

        // 文章を打っている途中の ⌥Z（Ω など）は、入力された記号そのものを文字として続ける。
        // 打ち終わってから押した場合は、通常どおりコンビネーションとして表示する。
        let optionOnly = flags == .maskAlternate || flags == [.maskAlternate, .maskShift]
        let optionSymbol = (isChar && optionOnly)
            ? KeyFormatter.optionSymbol(code, shifted: flags.contains(.maskShift))
            : nil
        let optionInTyping = typingIsLive && optionSymbol != nil

        // 修飾キーなし、または Shift のみの文字キーは「タイピング」として扱う
        let isTypingKey = (flags.isEmpty || shiftOnly)
            ? (isChar || spaceInTyping)
            : optionInTyping

        if isTypingKey {
            // 連打カウント付きの修飾キー行（⇧ ×n など）があれば、この押下はタイピングの
            // 始まりだったので 1 回ぶん差し戻して履歴化する。タイピング表示の有無に
            // かかわらず先に処理する（「すべてのキー入力を表示」オフでも ×n を正しく保つ）
            if let id = currentID, currentIsModifierOnly, entryCount(id) > 1 {
                model.decrement(id: id)
                model.release(id: id)
                currentID = nil
                currentIsModifierOnly = false
            }
            // ⌥ の記号を文章に続ける場合、直前に出した ⌥ 単独行は要らなくなるので消す
            if optionInTyping, let id = currentID, currentIsModifierOnly {
                model.remove(id: id)
                currentID = nil
                currentIsModifierOnly = false
            }
            // 通常タイピングは「すべてのキー入力を表示」がオンのときだけ表示する
            guard settings.showAllKeys else { return }
            let token: String
            if optionInTyping, let symbol = optionSymbol {
                // ⌥ で入力された記号そのものを文字として続ける（… Ω …）
                token = symbol
            } else if settings.kanaDisplay, KeyFormatter.isJapaneseInputMode(),
               let kana = KeyFormatter.kanaLabel(code, shifted: shiftOnly) {
                // かな入力モード: JIS かな配列のひらがな・記号で表示
                token = kana
            } else {
                // 文章に続けるスペースは Windows 表記でも「␣」のまま。
                // 「Space」だと文章の途中に単語が混ざって読めなくなるため。
                // 単独で押したときは特殊キーとして従来どおり表記設定に従う。
                token = KeyFormatter.keyLabel(
                    code, shifted: shiftOnly,
                    capsLock: event.flags.contains(.maskAlphaShift),
                    applyLabelStyle: false,
                    preserveCase: settings.distinguishCase
                )
            }
            // 既存の修飾キー単独行（⇧ など）はタイピング行へ置き換える
            if let id = currentID, currentIsModifierOnly {
                model.update(id: id, tokens: [token], isTyping: true)
                currentIsModifierOnly = false
                lastTypingID = id
                lastTypingTime = now
                return
            }
            // 直前のタイピング行へ連結
            if let id = lastTypingID,
               now - lastTypingTime < typingAppendWindow,
               model.phase(of: id) != nil,
               typingRowHasRoom(id: id, adding: token),
               model.append(id: id, token: token) {
                currentID = id
                lastTypingTime = now
                return
            }
            // 新しいタイピング行。
            // 直前の行は連結を打ち切られてここへ来る（行数上限での分割や連結時間切れ）。
            // 押しっぱなし扱いのまま取り残されると消えなくなるので、必ず解放する。
            let id = model.begin(tokens: [token], isTyping: true)
            model.releaseOtherTypingRows(except: id)
            currentID = id
            currentIsModifierOnly = false
            lastTypingID = id
            lastTypingTime = now
        } else if handleArrowGrouping(code: code, flags: flags, now: now) {
            // 矢印キーをまとめて表示した（→↓ の同時押しや連続操作）
            return
        } else {
            // コンボ（修飾キー付き、または特殊キー単独）
            // 🌐 キー（fn 単独押し）は「fn の変化」と「コード 179 の keyDown」が別々に届く。
            // fn を先に離した順序だと fn 単独行が先に残ってしまうので、
            // 🌐 を表示する前に取り除いて 1 打鍵 = 1 行にする
            if code == 179 {
                removeTrailingLoneFnRow()
            }
            var tokens = KeyFormatter.modifierTokens(flags, keyCode: code, pressOrder: modifierPressOrder)
                + [KeyFormatter.keyLabel(code, shifted: false)]
            // ⌥ と組み合わせて入力される記号を併記する（⌥E → ´）
            if settings.showOptionSymbols, flags == .maskAlternate || flags == [.maskAlternate, .maskShift],
               KeyFormatter.isCharacterKey(code),
               let symbol = KeyFormatter.optionSymbol(code, shifted: flags.contains(.maskShift)) {
                tokens.append(KeyFormatter.optionResultArrow)
                tokens.append(symbol)
            }
            lastTypingID = nil
            lastArrowID = nil
            model.releaseOtherTypingRows()
            if let id = currentID, currentIsModifierOnly {
                if let target = mergeTargetID(for: tokens, ignoring: id) {
                    // 同じコンビネーションの連続押し: 「⌘」単独行を破棄して既存行を ×n に
                    model.remove(id: id)
                    model.increment(id: target)
                    currentID = target
                } else if entryCount(id) > 1 {
                    // 連打カウント付きの行（⌘ ×3 など）は履歴として残し、コンボは新しい行に。
                    // この押下で加算した 1 回ぶんはコンボの始まりだったので差し戻す（×4 → ×3）
                    model.decrement(id: id)
                    model.release(id: id)
                    currentID = model.begin(tokens: tokens, isTyping: false)
                    lastComboID = currentID
                    lastComboTokens = tokens
                } else {
                    // 「⌘」表示中に C が押された → 「⌘C」へ更新
                    model.update(id: id, tokens: tokens, isTyping: false)
                    lastComboID = id
                    lastComboTokens = tokens
                }
                currentIsModifierOnly = false
            } else {
                if let target = mergeTargetID(for: tokens) {
                    model.increment(id: target)
                    currentID = target
                } else {
                    if let id = currentID { model.release(id: id) }
                    currentID = model.begin(tokens: tokens, isTyping: false)
                    lastComboID = currentID
                    lastComboTokens = tokens
                }
                currentIsModifierOnly = false
            }
        }
    }

    private func handleKeyUp(_ event: CGEvent) {
        let code = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        pressedKeys.remove(code)

        // 何かキーが残っているなら、押し続けた場合にその表示へ狭める
        guard pressedKeys.isEmpty else {
            if currentID != nil { armRowNarrow() }
            return
        }
        // 物理キーが 1 つも押されていないなら、押しっぱなし扱いのタイピング行は残らないはず。
        // 早いタイピングでキーの押下が重なった際の取り残しをここで確実に回収する。
        model.releaseOtherTypingRows(except: currentIsModifierOnly ? nil : currentID)
        if let id = currentID, !currentIsModifierOnly {
            if currentModifiers.isEmpty {
                model.release(id: id)
                currentID = nil
            } else {
                // 修飾キーはまだ押されている。押し続けるなら修飾キーだけの表示に狭める
                armRowNarrow()
            }
        }
    }

    /// 修飾キー + クリックをキー表示の行として出す
    private func handleMouseForDisplay(type: CGEventType, event: CGEvent, button: Int) {
        guard settings.showClickInKeyDisplay,
              settings.overlayVisible,
              !settings.hotCornerSuppressed else { return }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let flags = KeyFormatter.relevantFlags(event.flags)
            currentModifiers = flags
            // 押しっぱなしの文字キー（A を押しながらクリック、など）
            let heldChars = settings.showKeyClickCombo
                ? pressedKeys.filter { KeyFormatter.isCharacterKey($0) }.sorted()
                : []
            // 修飾キーか押しっぱなしの文字キーとの組み合わせのみ表示
            // （単独クリックはマウスハイライトが担当）
            guard !flags.isEmpty || !heldChars.isEmpty else { return }
            let charLabels = heldChars.map { KeyFormatter.keyLabel($0, shifted: false) }
            let tokens = KeyFormatter.modifierTokens(flags, pressOrder: modifierPressOrder)
                + charLabels
                + [KeyFormatter.clickToken(button: button)]

            // 押している文字キーが既にタイピング行として出ているなら、
            // 新しい行を作らずその行を組み合わせ表示へ変える（「A」＋「A🖱」の二重表示を防ぐ）
            if !charLabels.isEmpty,
               let id = currentID,
               model.phase(of: id) == .active,
               model.entries.first(where: { $0.id == id })?.tokens == charLabels {
                model.update(id: id, tokens: tokens, isTyping: false)
                mouseEntryID = id
                currentID = nil
                currentIsModifierOnly = false
                lastTypingID = nil
                lastComboID = id
                lastComboTokens = tokens
                return
            }
            lastTypingID = nil
            if let id = currentID, currentIsModifierOnly {
                if let target = mergeTargetID(for: tokens, ignoring: id) {
                    // 同じ「修飾キー + クリック」の連続: 既存行を ×n に
                    model.remove(id: id)
                    model.increment(id: target)
                    mouseEntryID = target
                } else if entryCount(id) > 1 {
                    // 連打カウント付きの行は履歴として残し、クリック行は新規に。
                    // この押下で加算した 1 回ぶんは差し戻す
                    model.decrement(id: id)
                    model.release(id: id)
                    mouseEntryID = model.begin(tokens: tokens, isTyping: false)
                    lastComboID = mouseEntryID
                    lastComboTokens = tokens
                } else {
                    // 「⌘」表示中にクリック → 「⌘ + クリック」へ転用
                    model.update(id: id, tokens: tokens, isTyping: false)
                    mouseEntryID = id
                    lastComboID = id
                    lastComboTokens = tokens
                }
                currentIsModifierOnly = false
                currentID = nil
            } else {
                if let target = mergeTargetID(for: tokens) {
                    model.increment(id: target)
                    mouseEntryID = target
                } else {
                    if let mid = mouseEntryID { model.release(id: mid) }
                    mouseEntryID = model.begin(tokens: tokens, isTyping: false)
                    lastComboID = mouseEntryID
                    lastComboTokens = tokens
                }
            }

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if let mid = mouseEntryID {
                mouseEntryID = nil
                let held = KeyFormatter.relevantFlags(event.flags)
                currentModifiers = held
                if held.isEmpty && pressedKeys.isEmpty {
                    model.release(id: mid)
                } else {
                    // 修飾キーを押し続けているなら、この行を押しているキーだけの表示に狭める
                    // （押しているのに何も表示されない状態を作らない）
                    currentID = mid
                    currentIsModifierOnly = false
                    armRowNarrow()
                }
            }

        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let code = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = KeyFormatter.relevantFlags(event.flags)
        // 押した順を記録する（押下順表示オプション用）
        for (flag, _) in KeyFormatter.modifierDisplayOrder
        where flags.contains(flag) && !currentModifiers.contains(flag) {
            modifierPressOrder.append(flag)
        }
        currentModifiers = flags
        // 修飾キーの状態が動いたので、保留していた処理はいったん取り消す
        // （必要ならこの後 armRowNarrow で組み直す）
        cancelModifierShrink()

        // Caps Lock はトグルなので一瞬だけ表示（連打は ×n にまとめる）
        if code == 57 {
            let tokens = [KeyFormatter.localized("⇪")]
            if let target = mergeTargetID(for: tokens) {
                model.increment(id: target)
                model.release(id: target)
            } else {
                let id = model.begin(tokens: tokens, isTyping: false)
                model.release(id: id)
                lastComboID = id
                lastComboTokens = tokens
            }
            return
        }

        if flags.isEmpty {
            suppressModifierEntry = false
            modifierPeak = []
            modifierPressOrder = []
            if let id = currentID {
                if pressedKeys.contains(where: { !KeyFormatter.modifierKeyCodes.contains($0) }) {
                    // 英数・かななど通常のキーがまだ押されている。
                    // 押し続けるならそのキーだけの表示に狭める
                    armRowNarrow()
                } else {
                    // 連打をまとめられるよう、離した行を記録しておく
                    lastComboTokens = model.entries.first(where: { $0.id == id })?.tokens
                    lastComboID = id
                    model.release(id: id)
                    currentID = nil
                    currentIsModifierOnly = false
                }
            }
        } else {
            if let id = currentID, currentIsModifierOnly {
                if entryCount(id) > 1 {
                    // 連打カウント付きの行（⌘ ×3 など）は残し、新しい修飾キー構成は新規行に。
                    // この押下で加算した 1 回ぶんは差し戻す
                    model.decrement(id: id)
                    model.release(id: id)
                    modifierPeak = flags
                    currentID = model.begin(tokens: KeyFormatter.modifierTokens(flags, pressOrder: modifierPressOrder), isTyping: false)
                } else if !flags.isSuperset(of: modifierPeak) {
                    // 修飾キーが減った。離しきる途中の一瞬で表示を変えないよう、
                    // 残りを押し続けたときだけ反映する（armRowNarrow を参照）
                    armRowNarrow()
                } else {
                    // 押し足した修飾キーは加えるが、離したぶんは消さない。
                    // 途中で片方を離しても「⇧⌘」のまま表示し続けるため。
                    modifierPeak.formUnion(flags)
                    model.update(id: id, tokens: KeyFormatter.modifierTokens(modifierPeak, pressOrder: modifierPressOrder), isTyping: false)
                }
            } else if currentID == nil, !suppressModifierEntry {
                // タイピングの連結が生きている間の Shift 単独押下は、大文字や
                // 小書きかな（ょ など）の入力操作の一部とみなして ⇧ 行を出さない。
                // これにより「きょう」や「Hello」が行分かれせず連続表示される。
                let now = ProcessInfo.processInfo.systemUptime
                if flags == .maskShift,
                   let tid = lastTypingID,
                   now - lastTypingTime < typingAppendWindow,
                   model.phase(of: tid) != nil {
                    return
                }
                let tokens = KeyFormatter.modifierTokens(flags, pressOrder: modifierPressOrder)
                if let target = mergeTargetID(for: tokens) {
                    // 同じ修飾キーの連続押し（⌘ 連打など）: 既存行を ×n に
                    model.increment(id: target)
                    modifierPeak = flags
                    currentID = target
                } else {
                    // 修飾キー単独の表示を開始
                    currentID = model.begin(tokens: tokens, isTyping: false)
                }
                currentIsModifierOnly = true
                // ⌥ と ⇧ は記号や大文字を打つのに使うので、タイピングの連結は切らない
                // （⌥Z で Ω を続けて打てるように）
                if !flags.subtracting([.maskAlternate, .maskShift]).isEmpty {
                    lastTypingID = nil
                }
            } else if let id = currentID, !currentIsModifierOnly, entryCount(id) == 1 {
                // 通常のキーを押したままで修飾キーの構成が変わった。
                // 押し続けるなら、いま押しているキーだけの表示に整える
                armRowNarrow()
            }
        }
    }
}
