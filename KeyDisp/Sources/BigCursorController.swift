import AppKit
import Combine
import SwiftUI

/// マウスカーソルに追従する大きなポインタ。
///
/// macOS のシステムカーソル自体を拡大することはアプリからはできない
/// （ポインタは常に全ウィンドウの最前面に描かれる）ため、
/// 同じ位置・同じ向きの大きなポインタを重ねて描くことで見やすくする。
final class BigCursorController {
    private let settings: AppSettings
    private let panel: NSPanel
    private let hosting: NSHostingView<BigCursorView>
    private var cancellables: Set<AnyCancellable> = []
    private var lastOrigin: NSPoint = .zero
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// ポインタ画像の周囲に確保する余白の割合（輪郭線と影のぶん）
    private static let padRatio: CGFloat = 0.18
    /// ポインタの縦横比（高さ 1 に対する幅）
    private static let aspect: CGFloat = 0.62

    init(settings: AppSettings = .shared) {
        self.settings = settings

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
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
        // isFloatingPanel はレベルを上書きするため、必ずその後に設定する
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none

        hosting = NSHostingView(rootView: BigCursorView(settings: settings))
        panel.contentView = hosting

        // 設定の変更（オン/オフ・大きさ・色）に追従する
        Publishers.CombineLatest3(
            settings.$bigCursor.removeDuplicates(),
            settings.$bigCursorSize.removeDuplicates(),
            settings.$bigCursorColorHex.removeDuplicates()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] enabled, _, _ in
            guard let self else { return }
            if enabled {
                self.installMouseMonitors()
                self.resize()
                self.follow()
                self.panel.orderFrontRegardless()
            } else {
                self.removeMouseMonitors()
                self.panel.orderOut(nil)
            }
        }
        .store(in: &cancellables)
    }

    /// マウス移動の購読。機能がオンの間だけ登録する。
    /// イベントタップで全マウス移動を受けると、機能オフでも移動のたびに
    /// プロセスが起床してしまうため、こちらのモニタ方式にしている。
    /// ドラッグ中の移動はタップの dragged イベントから mouseMoved() に転送される。
    private func installMouseMonitors() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.mouseMoved()
        }
        // 自アプリのウィンドウ上（設定画面など）ではグローバルモニタに届かないため
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.mouseMoved()
            return event
        }
    }

    private func removeMouseMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    /// マウスが動いたときに呼ぶ（モニタのほか、ドラッグ中はイベントタップから転送される）
    func mouseMoved() {
        guard settings.bigCursor else { return }
        if !panel.isVisible {
            resize()
            panel.orderFrontRegardless()
        }
        follow()
    }

    private func resize() {
        let h = CGFloat(settings.bigCursorSize)
        let pad = h * Self.padRatio
        panel.setContentSize(NSSize(width: h * Self.aspect + pad * 2, height: h + pad * 2))
    }

    /// ポインタの先端がカーソル位置に一致するよう配置する
    private func follow() {
        let loc = NSEvent.mouseLocation
        let pad = CGFloat(settings.bigCursorSize) * Self.padRatio
        let size = panel.frame.size
        let origin = NSPoint(x: loc.x - pad, y: loc.y - size.height + pad)
        guard abs(origin.x - lastOrigin.x) > 0.5 || abs(origin.y - lastOrigin.y) > 0.5 else { return }
        lastOrigin = origin
        panel.setFrameOrigin(origin)
    }
}

/// macOS の矢印ポインタを模した図形。先端が (0, 0) に来る単位座標で定義する。
struct BigCursorView: View {
    @ObservedObject var settings: AppSettings

    private static let outline: [CGPoint] = [
        CGPoint(x: 0.00, y: 0.00),  // 先端
        CGPoint(x: 0.00, y: 0.78),
        CGPoint(x: 0.19, y: 0.60),
        CGPoint(x: 0.31, y: 0.92),
        CGPoint(x: 0.45, y: 0.86),
        CGPoint(x: 0.33, y: 0.55),
        CGPoint(x: 0.58, y: 0.53),
    ]

    var body: some View {
        let h = CGFloat(settings.bigCursorSize)
        let pad = h * 0.18
        let fill = Color(nsColor: NSColor(hexString: settings.bigCursorColorHex) ?? .white)

        Path { p in
            let pts = Self.outline.map {
                CGPoint(x: pad + $0.x * h, y: pad + $0.y * h)
            }
            p.move(to: pts[0])
            for pt in pts.dropFirst() { p.addLine(to: pt) }
            p.closeSubpath()
        }
        .fill(fill)
        .overlay(
            Path { p in
                let pts = Self.outline.map {
                    CGPoint(x: pad + $0.x * h, y: pad + $0.y * h)
                }
                p.move(to: pts[0])
                for pt in pts.dropFirst() { p.addLine(to: pt) }
                p.closeSubpath()
            }
            .stroke(Color.black.opacity(0.85), lineWidth: max(1.5, h * 0.045))
        )
        .shadow(color: .black.opacity(0.35), radius: h * 0.05, y: h * 0.02)
        .frame(width: h * 0.62 + pad * 2, height: h + pad * 2)
    }
}
