import Foundation
import Combine

/// 画面に表示する 1 行分のキー入力
struct KeyEntry: Identifiable, Equatable {
    enum Phase: Equatable {
        case active   // キーが押されている間
        case holding  // 離した後、設定時間だけ表示を維持
        case fading   // フェードアウト中
    }

    let id: UUID
    var tokens: [String]     // 例: ["⌘", "⇧", "S"] / タイピングなら ["H", "E", "L"]
    var isTyping: Bool
    var phase: Phase
    /// 同じキーが連続で押された回数（2 以上で ×n バッジを表示）
    var count: Int = 1

    var text: String { tokens.joined() }
}

/// 表示中のエントリ一覧と、そのライフサイクル（保持→フェード→削除）を管理する
final class KeyDisplayModel: ObservableObject {
    @Published private(set) var entries: [KeyEntry] = []

    private let settings: AppSettings
    private var pendingWork: [UUID: [DispatchWorkItem]] = [:]

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    @discardableResult
    func begin(tokens: [String], isTyping: Bool) -> UUID {
        let entry = KeyEntry(id: UUID(), tokens: tokens, isTyping: isTyping, phase: .active)
        entries.append(entry)
        trimRows()
        return entry.id
    }

    func update(id: UUID, tokens: [String], isTyping: Bool? = nil) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].tokens = tokens
        // 内容が変わった行は別の入力になったということなので、連続カウントはリセット
        entries[idx].count = 1
        if let isTyping { entries[idx].isTyping = isTyping }
    }

    /// タイピング中のエントリへ 1 文字追加。エントリが既に消えかけなら false。
    func append(id: UUID, token: String) -> Bool {
        guard let idx = entries.firstIndex(where: { $0.id == id }),
              entries[idx].phase != .fading else { return false }
        cancelWork(for: id)
        entries[idx].tokens.append(token)
        entries[idx].phase = .active
        return true
    }

    /// キーを離した: 保持時間ののちフェードアウトさせる
    func release(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }),
              entries[idx].phase == .active else { return }
        cancelWork(for: id)
        entries[idx].phase = .holding

        let fade = DispatchWorkItem { [weak self] in
            guard let self, let i = self.entries.firstIndex(where: { $0.id == id }) else { return }
            self.entries[i].phase = .fading
        }
        let remove = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.entries.removeAll { $0.id == id }
            self.pendingWork[id] = nil
        }
        pendingWork[id] = [fade, remove]
        let hold = max(0, settings.holdDuration)
        let fadeLen = max(0.05, settings.fadeDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: fade)
        DispatchQueue.main.asyncAfter(deadline: .now() + hold + fadeLen + 0.1, execute: remove)
    }

    /// タイピング行は同時に 1 つだけ生きていればよい。行の分割や連結の打ち切りで
    /// 取り残された行（押しっぱなし扱いのまま消えない行）を解放する。
    func releaseOtherTypingRows(except id: UUID? = nil) {
        for entry in entries where entry.isTyping && entry.phase == .active && entry.id != id {
            release(id: entry.id)
        }
    }

    /// 同じキーの連続入力: 回数を増やして表示を維持する
    func increment(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        cancelWork(for: id)
        entries[idx].count += 1
        entries[idx].phase = .active
    }

    /// 連続カウントを 1 つ戻す（連打だと思ってマージした押下が、実はコンビネーションの
    /// 始まりだったと判明したときの差し戻し用）
    func decrement(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].count = max(1, entries[idx].count - 1)
    }

    /// エントリを即座に削除する（回数マージで不要になった行の破棄用）
    func remove(id: UUID) {
        cancelWork(for: id)
        entries.removeAll { $0.id == id }
    }

    /// Caps Lock 切替えなど、押しっぱなし判定のない一瞬の表示
    func flash(tokens: [String]) {
        let id = begin(tokens: tokens, isTyping: false)
        release(id: id)
    }

    func phase(of id: UUID) -> KeyEntry.Phase? {
        entries.first(where: { $0.id == id })?.phase
    }

    func clearAll() {
        for id in pendingWork.keys { cancelWork(for: id) }
        entries.removeAll()
    }

    private func trimRows() {
        let maxRows = max(1, Int(settings.maxRows))
        while entries.count > maxRows {
            let removed = entries.removeFirst()
            cancelWork(for: removed.id)
        }
    }

    private func cancelWork(for id: UUID) {
        pendingWork[id]?.forEach { $0.cancel() }
        pendingWork[id] = nil
    }
}
