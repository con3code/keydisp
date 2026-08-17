import AppKit

/// システムのカラーパネルを、操作している（カーソルのある）画面へ連れてくる。
/// 設定画面や編集 HUD はメニューを操作した画面に出すようにしたが、カラーパネルは
/// システムが以前の位置を記憶しているため、別の画面に現れてしまうことがある。
/// パネルがキーになった（= クリックで開かれた・前面化された）タイミングで検査して移す。
final class ColorPanelScreenFollower {
    private var observer: Any?

    private var wasVisible = false

    func install() {
        guard observer == nil else { return }
        wasVisible = NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible
        // カラーパネルはキーウィンドウにならないことがあるため、
        // 表示状態の変化（occlusion）で「開かれた瞬間」を捉える
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, let panel = note.object as? NSColorPanel else { return }
            let visible = panel.isVisible
            defer { self.wasVisible = visible }
            // 非表示 → 表示 になった瞬間だけ動かす（重なり順の変化などでは動かさない）
            guard visible, !self.wasVisible else { return }
            Self.bringToCursorScreen(panel)
        }
    }

    /// カーソルのある画面に無ければ、相対位置を保ってその画面へ移す。
    /// パネル自体をクリックした場合はカーソルが同じ画面にあるので動かない
    static func bringToCursorScreen(_ panel: NSWindow) {
        let loc = NSEvent.mouseLocation
        guard let target = NSScreen.screens.first(where: { $0.frame.contains(loc) }) else { return }
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard !target.frame.contains(center) else { return }

        var f = panel.frame
        if let source = NSScreen.screens.first(where: { $0.frame.contains(center) })?.visibleFrame {
            f = OverlayWindowController.remap(f, from: source, to: target.visibleFrame)
        }
        let v = target.visibleFrame
        f.origin.x = max(v.minX, min(f.origin.x, v.maxX - f.width))
        f.origin.y = max(v.minY, min(f.origin.y, v.maxY - f.height))
        panel.setFrameOrigin(f.origin)
    }
}
