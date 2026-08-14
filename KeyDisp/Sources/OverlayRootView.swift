import SwiftUI

/// オーバーレイウィンドウの中身。
/// 下端に揃えてキー入力の行が積み上がり、新しい行が入ると古い行が上へスライドする。
struct OverlayRootView: View {
    @ObservedObject var model: KeyDisplayModel
    @ObservedObject var settings: AppSettings

    /// 編集モードでプレビューするサンプル行（積み上げ行数設定に合わせて先頭から使う）
    private static let samples: [KeyEntry] = [
        KeyEntry(id: UUID(), tokens: ["⌃", "⌥", "⌫"], isTyping: false, phase: .holding),
        KeyEntry(id: UUID(), tokens: ["⇧", "⇥"], isTyping: false, phase: .holding),
        KeyEntry(id: UUID(), tokens: ["F3"], isTyping: false, phase: .holding),
        KeyEntry(id: UUID(), tokens: ["⌘", "␣"], isTyping: false, phase: .holding),
        KeyEntry(id: UUID(), tokens: ["⎋"], isTyping: false, phase: .holding, count: 2),
        KeyEntry(id: UUID(), tokens: ["⌘", "⇧", "S"], isTyping: false, phase: .holding),
        KeyEntry(id: UUID(), tokens: ["H", "E", "L", "L", "O"], isTyping: true, phase: .holding),
        KeyEntry(id: UUID(), tokens: ["⌘", "«click»"], isTyping: false, phase: .active),
    ]

    private var displayEntries: [KeyEntry] {
        if settings.editMode && model.entries.isEmpty {
            let rows = max(1, min(Self.samples.count, Int(settings.maxRows)))
            return Array(Self.samples.suffix(rows))
        }
        return model.entries
    }

    var body: some View {
        GeometryReader { geo in
            let rowMaxWidth = max(60, geo.size.width - 32)
            ZStack(alignment: .topLeading) {
                if settings.editMode {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundColor(.accentColor.opacity(0.8))
                        .background(Color.black.opacity(0.06).cornerRadius(12))
                }

                VStack(alignment: .leading, spacing: 8 * settings.displayScale) {
                    ForEach(settings.stackFromTop ? Array(displayEntries.reversed()) : displayEntries) { entry in
                        KeyEntryRow(entry: entry, settings: settings, maxWidth: rowMaxWidth)
                            .opacity(entry.phase == .fading ? 0 : 1)
                            .animation(.easeOut(duration: settings.fadeDuration), value: entry.phase)
                            .transition(.asymmetric(
                                insertion: .move(edge: settings.stackFromTop ? .top : .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                .padding(16)
                .frame(
                    maxWidth: .infinity, maxHeight: .infinity,
                    alignment: settings.stackFromTop ? .topLeading : .bottomLeading
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: model.entries)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 幅に収まらない要素を次の行へ折り返すレイアウト
struct FlowLayout: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0
        var rowHeight: CGFloat = 0, totalWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var line: [(subview: LayoutSubviews.Element, size: CGSize)] = []
        var lineWidth: CGFloat = 0

        func flushLine() {
            guard !line.isEmpty else { return }
            let rowHeight = line.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for item in line {
                // 行内で縦センタリングして配置する（キーキャップと「+」の高さを揃える）
                let itemY = y + (rowHeight - item.size.height) / 2
                item.subview.place(at: CGPoint(x: x, y: itemY), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += rowHeight + spacing
            line.removeAll()
            lineWidth = 0
        }

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if !line.isEmpty && lineWidth + size.width > bounds.width {
                flushLine()
            }
            line.append((sub, size))
            lineWidth += size.width + spacing
        }
        flushLine()
    }
}

/// 1 行分のキー表示
struct KeyEntryRow: View {
    let entry: KeyEntry
    @ObservedObject var settings: AppSettings
    /// オーバーレイの幅に合わせた 1 行の最大幅。超えた分は折り返す。
    var maxWidth: CGFloat = .infinity

    private var fontSize: CGFloat { 34 * settings.displayScale }
    private var textColor: Color { Color(nsColor: settings.textColor) }
    private var keyColor: Color { Color(nsColor: settings.keyColor) }
    private var bgOpacity: Double { settings.backgroundEnabled ? settings.backgroundOpacity : 0 }

    /// コンビネーション表示のみ「+」区切りを入れる（タイピングの連結には入れない）
    private var showPlus: Bool { settings.plusSeparator && !entry.isTyping }

    /// トークン列を Text として連結する（クリックトークンはカーソル画像に置き換え）
    private var displayText: Text {
        var result = Text("")
        for (i, token) in entry.tokens.enumerated() {
            if i > 0 && showPlus { result = result + Text("+") }
            if let symbol = KeyFormatter.clickSymbolName(for: token) {
                result = result + Text(Image(systemName: symbol))
            } else if settings.globeOnImeKeys, KeyFormatter.isImeSwitchToken(token) {
                result = result + Text(Image(systemName: "globe")) + Text(token)
            } else {
                result = result + Text(token)
            }
        }
        if entry.count > 1 {
            result = result + Text(" ×\(entry.count)")
                .font(.system(size: fontSize * 0.6, weight: .heavy, design: .rounded))
        }
        return result
    }

    @State private var pulseScale: CGFloat = 1
    @State private var lastPulseTime: TimeInterval = 0

    var body: some View {
        styledBody
            .scaleEffect(pulseScale, anchor: .bottomLeading)
            .onChange(of: entry.count) { _ in
                // カウント増加時のパルス（autorepeat の高頻度更新では間引く）
                let now = ProcessInfo.processInfo.systemUptime
                guard now - lastPulseTime > 0.12 else { return }
                lastPulseTime = now
                pulseScale = 1.1
                withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
                    pulseScale = 1
                }
            }
    }

    @ViewBuilder
    private var styledBody: some View {
        switch settings.style {
        case .simple:
            displayText
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14 * settings.displayScale)
                .padding(.vertical, 7 * settings.displayScale)
                .background(
                    RoundedRectangle(cornerRadius: 14 * settings.displayScale, style: .continuous)
                        .fill(keyColor.opacity(bgOpacity))
                )
                .frame(maxWidth: maxWidth, alignment: .leading)

        case .keycap:
            FlowLayout(spacing: 5 * settings.displayScale) {
                ForEach(Array(entry.tokens.enumerated()), id: \.offset) { index, token in
                    if index > 0 && showPlus {
                        Text("+")
                            .font(.system(size: 20 * settings.displayScale, weight: .bold, design: .rounded))
                            .foregroundColor(textColor)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    KeycapView(token: token, settings: settings)
                }
                if entry.count > 1 {
                    Text("×\(entry.count)")
                        .font(.system(size: 22 * settings.displayScale, weight: .heavy, design: .rounded))
                        .foregroundColor(textColor)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
            }
            .frame(maxWidth: maxWidth, alignment: .leading)

        case .customImage:
            displayText
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 22 * settings.displayScale)
                .padding(.vertical, 10 * settings.displayScale)
                .background(customBackground)
                .frame(maxWidth: maxWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private var customBackground: some View {
        if !settings.customImagePath.isEmpty,
           let image = NSImage(contentsOfFile: settings.customImagePath) {
            Image(nsImage: image)
                .resizable(
                    capInsets: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24),
                    resizingMode: .stretch
                )
                .opacity(settings.backgroundEnabled ? settings.backgroundOpacity : 1)
        } else {
            RoundedRectangle(cornerRadius: 12 * settings.displayScale)
                .fill(keyColor.opacity(bgOpacity))
        }
    }
}

/// キーキャップ風の 1 キー表示
struct KeycapView: View {
    let token: String
    @ObservedObject var settings: AppSettings

    private var scale: CGFloat { settings.displayScale }
    private var fontSize: CGFloat { 30 * scale }
    private var keyColor: Color { Color(nsColor: settings.keyColor) }
    private var textColor: Color { Color(nsColor: settings.textColor) }
    private var opacity: Double { settings.backgroundEnabled ? settings.backgroundOpacity : 0.15 }

    var body: some View {
        labelView
            .foregroundColor(textColor)
            .lineLimit(1)
            .frame(minWidth: 38 * scale)
            .padding(.horizontal, 7 * scale)
            .padding(.vertical, 7 * scale)
            .background(
                ZStack {
                    // 下側の縁（キーの厚み）
                    RoundedRectangle(cornerRadius: 10 * scale)
                        .fill(keyColor.opacity(opacity))
                        .offset(y: 3.5 * scale)
                        .brightness(-0.18)
                    // キートップ
                    RoundedRectangle(cornerRadius: 10 * scale)
                        .fill(
                            LinearGradient(
                                colors: [
                                    keyColor.opacity(opacity),
                                    keyColor.opacity(opacity * 0.85),
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    RoundedRectangle(cornerRadius: 10 * scale)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
            )
            .shadow(color: .black.opacity(0.35), radius: 3 * scale, y: 2 * scale)
            .fixedSize()
    }

    /// 通常キーは文字、クリックトークンはカーソル画像、入力切替キーは 🌐 付きで描画する
    @ViewBuilder
    private var labelView: some View {
        if let symbol = KeyFormatter.clickSymbolName(for: token) {
            Image(systemName: symbol)
                .font(.system(size: fontSize, weight: .bold))
        } else if settings.globeOnImeKeys, KeyFormatter.isImeSwitchToken(token) {
            (Text(Image(systemName: "globe")) + Text(token))
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
        } else {
            Text(token)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
        }
    }
}
