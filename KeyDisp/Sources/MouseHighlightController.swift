import AppKit
import SwiftUI

/// クリック / プレス（ドラッグ）中にマウスカーソルの位置へ円形ハイライトを表示する。
/// 左クリック = 塗りつぶし円、右クリック = 二重リング。
final class MouseHighlightController {
    private let settings: AppSettings
    private let panel: NSPanel
    private let hosting: NSHostingView<MouseHighlightView>
    private var pressedButtons: Set<Int> = []
    private var fadeWorkItem: DispatchWorkItem?

    init(settings: AppSettings = .shared) {
        self.settings = settings

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // キー表示や編集 HUD よりも上、常に最前面
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none

        hosting = NSHostingView(rootView: MouseHighlightView(settings: settings, button: 0))
        panel.contentView = hosting
    }

    /// イベントタップから転送されるマウスイベントを処理する（メインスレッド）
    func handle(type: CGEventType, buttonNumber: Int) {
        guard settings.mouseHighlight else {
            if !pressedButtons.isEmpty {
                pressedButtons.removeAll()
                panel.orderOut(nil)
            }
            return
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            pressedButtons.insert(buttonNumber)
            fadeWorkItem?.cancel()
            fadeWorkItem = nil
            hosting.rootView = MouseHighlightView(settings: settings, button: buttonNumber)
            let d = CGFloat(settings.mouseHighlightSize) + 24
            panel.setContentSize(NSSize(width: d, height: d))
            moveToCursor()
            panel.alphaValue = 1
            panel.orderFrontRegardless()

        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            if !pressedButtons.isEmpty { moveToCursor() }

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            pressedButtons.remove(buttonNumber)
            if pressedButtons.isEmpty { fadeOut() }

        default:
            break
        }
    }

    private func moveToCursor() {
        let loc = NSEvent.mouseLocation
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: loc.x - size.width / 2, y: loc.y - size.height / 2))
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }
        let work = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
            self?.panel.alphaValue = 1
        }
        fadeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27, execute: work)
    }
}

struct MouseHighlightView: View {
    @ObservedObject var settings: AppSettings
    let button: Int

    private var color: Color {
        Color(nsColor: NSColor(hexString: settings.mouseColorHex) ?? .orange)
    }

    var body: some View {
        let d = CGFloat(settings.mouseHighlightSize)
        ZStack {
            if button == 1 {
                // 右クリック: 二重リング
                Circle()
                    .strokeBorder(color, lineWidth: 4)
                    .frame(width: d, height: d)
                Circle()
                    .strokeBorder(color.opacity(0.6), lineWidth: 2.5)
                    .frame(width: d * 0.62, height: d * 0.62)
            } else {
                // 左クリック・その他: 塗りつぶし + リング
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: d, height: d)
                Circle()
                    .strokeBorder(color, lineWidth: 3)
                    .frame(width: d, height: d)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
