import AppKit
import CoreGraphics

/// CGEventTap でキーボードイベントを監視し、KeyDisplayModel へ流し込む
final class KeyCaptureController {
    private let model: KeyDisplayModel
    private let settings: AppSettings

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

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
    /// コンビネーションの後も押し続けている修飾キーを、改めて表示するための処理
    private var reshowWork: DispatchWorkItem?
    /// この時間だけ押し続けたら「意図して押している」とみなす。
    /// これより早く離した場合は 1 回の操作の一部として扱う。
    private let deliberateHoldDelay: TimeInterval = 0.5
    /// コンボのキーを離した後、修飾キーだけが残っている間は
    /// 修飾キー単独行を出さないためのフラグ
    private var suppressModifierEntry = false
    /// 修飾キー + クリックの表示行
    private var mouseEntryID: UUID?
    /// 直前のコンビネーション行（同じキーの連続押しを ×n にまとめる判定用）
    private var lastComboID: UUID?
    private var lastComboTokens: [String]?
    /// タイピング（修飾なし文字入力)の連結用
    private var lastTypingID: UUID?
    private var lastTypingTime: TimeInterval = 0
    private let typingAppendWindow: TimeInterval = 1.2
    private let maxTypingTokens = 16

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
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue)

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
        isRunning = true
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
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
        cancelModifierShrink()
        cancelModifierReshow()
        suppressModifierEntry = false
        lastTypingID = nil
        mouseEntryID = nil
        lastComboID = nil
        lastComboTokens = nil
    }

    // MARK: - 修飾キーが減ったときの保留処理

    private func cancelModifierShrink() {
        modifierShrinkWork?.cancel()
        modifierShrinkWork = nil
    }

    /// 修飾キーの一部を離した状態で `deliberateHoldDelay` だけ押し続けたときの処理を予約する。
    /// - 「離すたびに履歴を残す」オン: そこまでの組み合わせを履歴として確定し、残りを新しい行にする
    /// - オフ: 行は増やさず、同じ行を残りのキーだけの表示へ更新する
    ///
    /// どちらも、それより早く離しきった場合は取り消され、押した組み合わせ全体が 1 行として残る。
    private func armModifierShrink(remaining: CGEventFlags) {
        cancelModifierShrink()
        guard !remaining.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  let id = self.currentID,
                  self.currentIsModifierOnly,
                  self.entryCount(id) == 1 else { return }
            let tokens = KeyFormatter.modifierTokens(remaining)
            if self.settings.stepModifierRelease {
                self.model.release(id: id)
                self.lastComboID = id
                self.lastComboTokens = self.model.entries.first(where: { $0.id == id })?.tokens
                self.currentID = self.model.begin(tokens: tokens, isTyping: false)
            } else {
                self.model.update(id: id, tokens: tokens, isTyping: false)
            }
            self.modifierPeak = remaining
            self.modifierShrinkWork = nil
        }
        modifierShrinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + deliberateHoldDelay, execute: work)
    }

    // MARK: - コンビネーション後に押し続けている修飾キーの再表示

    private func cancelModifierReshow() {
        reshowWork?.cancel()
        reshowWork = nil
    }

    /// コンビネーション（⌘C や ⌘+クリックなど）を終えた後も修飾キーを押し続けている場合、
    /// `deliberateHoldDelay` 待ってから修飾キー単独の行を出し直す。
    /// すぐ離す・続けて次の操作をする場合は取り消されるので、余計な行は増えない。
    private func armModifierReshow(_ flags: CGEventFlags) {
        cancelModifierReshow()
        guard !flags.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.currentID == nil,
                  self.mouseEntryID == nil,
                  self.currentModifiers == flags else { return }
            self.suppressModifierEntry = false
            self.modifierPeak = flags
            self.currentIsModifierOnly = true
            self.lastTypingID = nil
            self.currentID = self.model.begin(
                tokens: KeyFormatter.modifierTokens(flags), isTyping: false
            )
            self.reshowWork = nil
        }
        reshowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + deliberateHoldDelay, execute: work)
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
        case .mouseMoved:
            onMouseMoved?()
            return
        case .leftMouseDown, .leftMouseUp,
             .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            onMouseMoved?()
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            onMouseEvent?(type, button)
            handleMouseForDisplay(type: type, event: event, button: button)
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
    }

    private func handleKeyDown(_ event: CGEvent) {
        // 長押しの autorepeat は、コンビネーション/特殊キー行のカウントとして数える
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            if settings.countRepeats, let id = currentID, !currentIsModifierOnly,
               model.entries.first(where: { $0.id == id })?.isTyping == false {
                model.increment(id: id)
            }
            return
        }
        let code = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        pressedKeys.insert(code)
        // 文字キーが押されたなら修飾キー行はコンビネーションへ変わるので、保留中の処理は破棄する
        cancelModifierShrink()
        cancelModifierReshow()

        let flags = KeyFormatter.relevantFlags(event.flags)
        currentModifiers = flags
        let shiftOnly = flags == .maskShift
        let isChar = KeyFormatter.isCharacterKey(code)
        // 修飾キーなし、または Shift のみの文字キーは「タイピング」として扱う
        let isTypingKey = isChar && (flags.isEmpty || shiftOnly)

        let now = ProcessInfo.processInfo.systemUptime

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
            // 通常タイピングは「すべてのキー入力を表示」がオンのときだけ表示する
            guard settings.showAllKeys else { return }
            let token: String
            if settings.kanaDisplay, KeyFormatter.isJapaneseInputMode(),
               let kana = KeyFormatter.kanaLabel(code, shifted: shiftOnly) {
                // かな入力モード: JIS かな配列のひらがな・記号で表示
                token = kana
            } else {
                token = KeyFormatter.keyLabel(
                    code, shifted: shiftOnly,
                    capsLock: event.flags.contains(.maskAlphaShift),
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
               (model.entries.first(where: { $0.id == id })?.tokens.count ?? maxTypingTokens) < maxTypingTokens,
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
        } else {
            // コンボ（修飾キー付き、または特殊キー単独）
            let tokens = KeyFormatter.modifierTokens(flags, keyCode: code) + [KeyFormatter.keyLabel(code, shifted: false)]
            lastTypingID = nil
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

        guard pressedKeys.isEmpty else { return }
        // 物理キーが 1 つも押されていないなら、押しっぱなし扱いのタイピング行は残らないはず。
        // 早いタイピングでキーの押下が重なった際の取り残しをここで確実に回収する。
        model.releaseOtherTypingRows(except: currentIsModifierOnly ? nil : currentID)
        if let id = currentID, !currentIsModifierOnly {
            model.release(id: id)
            currentID = nil
            // 修飾キーがまだ押されている間は、修飾キー単独行をすぐには出さない。
            // ただし押し続けているなら少し後に出し直す（何も表示されない状態を作らない）
            suppressModifierEntry = !currentModifiers.isEmpty
            armModifierReshow(currentModifiers)
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
            // 修飾キーとの組み合わせのみ表示（単独クリックはマウスハイライトが担当）
            guard !flags.isEmpty else { return }
            let tokens = KeyFormatter.modifierTokens(flags) + [KeyFormatter.clickToken(button: button)]
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
                model.release(id: mid)
                mouseEntryID = nil
                // クリックを終えても修飾キーを押し続けているなら、少し後に修飾キー行を
                // 出し直す（押しているのに何も表示されない状態を作らない）
                let held = KeyFormatter.relevantFlags(event.flags)
                currentModifiers = held
                suppressModifierEntry = !held.isEmpty
                armModifierReshow(held)
            }

        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let code = CGKeyCode(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let flags = KeyFormatter.relevantFlags(event.flags)
        currentModifiers = flags
        // 修飾キーの状態が動いたので、保留していた処理はいったん取り消す
        // （必要ならこの後 armStepCommit / armModifierReshow で組み直す）
        cancelModifierShrink()
        cancelModifierReshow()

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
            if let id = currentID, currentIsModifierOnly {
                // 修飾キー単独行の連打をまとめられるよう、離した行を記録しておく
                lastComboTokens = model.entries.first(where: { $0.id == id })?.tokens
                lastComboID = id
                model.release(id: id)
                currentID = nil
                currentIsModifierOnly = false
            }
        } else {
            if let id = currentID, currentIsModifierOnly {
                if entryCount(id) > 1 {
                    // 連打カウント付きの行（⌘ ×3 など）は残し、新しい修飾キー構成は新規行に。
                    // この押下で加算した 1 回ぶんは差し戻す
                    model.decrement(id: id)
                    model.release(id: id)
                    modifierPeak = flags
                    currentID = model.begin(tokens: KeyFormatter.modifierTokens(flags), isTyping: false)
                } else if !flags.isSuperset(of: modifierPeak) {
                    // 修飾キーが減った。離しきる途中の一瞬で表示を変えないよう、
                    // 残りを押し続けたときだけ反映する（armModifierShrink を参照）
                    armModifierShrink(remaining: flags)
                } else {
                    // 押し足した修飾キーは加えるが、離したぶんは消さない。
                    // 途中で片方を離しても「⇧⌘」のまま表示し続けるため。
                    modifierPeak.formUnion(flags)
                    model.update(id: id, tokens: KeyFormatter.modifierTokens(modifierPeak), isTyping: false)
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
                let tokens = KeyFormatter.modifierTokens(flags)
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
                lastTypingID = nil
            } else if currentID == nil, suppressModifierEntry {
                // コンビネーションの後、修飾キーの構成が変わってもまだ押し続けている。
                // そのまま押し続けるなら改めて表示する
                armModifierReshow(flags)
            }
        }
    }
}
