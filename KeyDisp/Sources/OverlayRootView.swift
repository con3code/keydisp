import SwiftUI

/// キー表示の寸法計算。表示側とウィンドウ側で同じ値を使うためにここへまとめる。
enum OverlayMetrics {
    /// 折り返しのないキー表示 1 行ぶんの高さの目安
    static func rowHeight(_ settings: AppSettings) -> CGFloat {
        let scale = CGFloat(settings.displayScale)
        switch settings.style {
        case .keycap:      return 56 * scale  // 文字 30pt + padding 7pt×2 + 厚み
        case .simple:      return 58 * scale  // 文字 34pt + padding 7pt×2
        case .customImage: return 64 * scale  // 文字 34pt + padding 10pt×2
        }
    }

    static func rowSpacing(_ settings: AppSettings) -> CGFloat {
        8 * CGFloat(settings.displayScale)
    }

    /// 表示領域の内側の余白（上下合計）
    static let padding: CGFloat = 32

    /// 指定した行数を表示するのに必要な高さ
    static func requiredHeight(rows: Int, settings: AppSettings) -> CGFloat {
        let rows = CGFloat(max(1, rows))
        return rows * rowHeight(settings) + (rows - 1) * rowSpacing(settings) + padding
    }

    /// トークン 1 個ぶんの幅の目安（折り返し位置の計算用）。
    /// Windows 表記の「Ctrl」「BackSpace」のような複数文字のラベルは
    /// 記号 1 つのキーよりずっと横に広いので、ラベルを実際に測って見積もる。
    static func tokenWidth(_ token: String, settings: AppSettings) -> CGFloat {
        let scale = CGFloat(settings.displayScale)
        switch settings.style {
        case .keycap:               return keycapWidth(token) * scale
        case .simple, .customImage: return textWidth(token) * scale
        }
    }

    /// 表示倍率 1 のときのキーキャップ 1 個ぶんの幅（隣との間隔込み）
    private static var keycapWidthCache: [String: CGFloat] = [:]
    private static func keycapWidth(_ token: String) -> CGFloat {
        if let w = keycapWidthCache[token] { return w }
        let font = NSFont.systemFont(ofSize: 30, weight: .bold)
        let textWidth = (token as NSString).size(withAttributes: [.font: font]).width
        // KeycapView の最小幅 38 + 左右余白 7×2 + 隣との間隔 5
        let w = max(38, textWidth) + 14 + 5
        keycapWidthCache[token] = w
        return w
    }

    /// 表示倍率 1 のときの文字トークンの幅（シンプル / カスタム画像の 34pt 文字）。
    /// 実際の描画と同じ書体（丸みのあるシステムフォント）で測る。
    private static var textWidthCache: [String: CGFloat] = [:]
    private static let typingFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 34, weight: .semibold)
        if let desc = base.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: desc, size: 34) {
            return rounded
        }
        return base
    }()
    private static func textWidth(_ token: String) -> CGFloat {
        if let w = textWidthCache[token] { return w }
        let w = (token as NSString).size(withAttributes: [.font: typingFont]).width
        textWidthCache[token] = w
        return w
    }

    /// キーとキーの間の区切りが占める幅（「+」または細いスペース）
    static func separatorWidth(_ settings: AppSettings) -> CGFloat {
        let scale = CGFloat(settings.displayScale)
        switch settings.style {
        case .keycap:
            return settings.plusSeparator ? 18 * scale : 0
        case .simple, .customImage:
            return textWidth(settings.plusSeparator ? "+" : "\u{2009}") * scale
        }
    }

    /// タイプライター式の行（キーキャップ / カスタム画像）に、
    /// このトークン列が 1 行のまま収まるかどうか
    static func typingLineFits(_ tokens: [String], width: CGFloat, settings: AppSettings) -> Bool {
        let needed = tokens.reduce(0) { $0 + tokenWidth($1, settings: settings) }
        switch settings.style {
        case .keycap:
            return needed <= width
        case .customImage:
            // 行の背景の内側余白（左右 22 ずつ）のぶんだけ文字の領域は狭い
            return needed <= width - 44 * CGFloat(settings.displayScale)
        case .simple:
            return true
        }
    }

    /// 折り返して増えた 1 行ぶんの高さ
    static func extraLineHeight(_ settings: AppSettings) -> CGFloat {
        let scale = CGFloat(settings.displayScale)
        switch settings.style {
        case .keycap:               return 55 * scale
        case .simple, .customImage: return 41 * scale
        }
    }

    /// キーが 1 つずつ独立して並ぶスタイルかどうか。
    /// この場合は文字を流し込む折り返しではなく、行を改めるタイプライター式が合う。
    static func usesTypewriterWrap(_ settings: AppSettings) -> Bool {
        switch settings.style {
        case .keycap, .customImage: return true
        case .simple:               return false
        }
    }

    /// トークンを順に並べて、折り返して何行になるかを見積もる
    static func wrappedLines(
        tokens: [String], isTyping: Bool, width: CGFloat, settings: AppSettings
    ) -> Int {
        let gap = isTyping ? 0 : separatorWidth(settings)
        var lines = 1
        var used: CGFloat = 0
        for token in tokens {
            let w = tokenWidth(token, settings: settings)
            let need = used > 0 ? gap + w : w
            if used > 0 && used + need > width {
                lines += 1
                used = w
            } else {
                used += need
            }
        }
        return lines
    }

    /// 1 行が折り返しも含めて占める高さ
    static func height(of entry: KeyEntry, width: CGFloat, settings: AppSettings) -> CGFloat {
        let lines = wrappedLines(
            tokens: entry.tokens, isTyping: entry.isTyping, width: width, settings: settings
        )
        return rowHeight(settings) + CGFloat(lines - 1) * extraLineHeight(settings)
    }

    /// 表示領域に収まる行だけを返す（新しい方を優先し、古い行から落とす）。
    /// いちばん新しい行だけで収まらない場合は、その行の古い文字を落として収める。
    static func visibleRows(_ entries: [KeyEntry], size: CGSize, settings: AppSettings) -> [KeyEntry] {
        guard !entries.isEmpty else { return [] }
        let availH = max(1, size.height - padding)
        let availW = max(1, size.width - padding)
        var result: [KeyEntry] = []
        var used: CGFloat = 0

        for entry in entries.reversed() {
            let h = height(of: entry, width: availW, settings: settings)
            let need = result.isEmpty ? h : h + rowSpacing(settings)
            if used + need > availH {
                if result.isEmpty {
                    // 1 行だけでも収まらない: 新しい文字を残して先頭を削る
                    var trimmed = entry
                    let maxLines = max(1, Int((availH - rowHeight(settings)) / extraLineHeight(settings)) + 1)
                    trimmed.tokens = tokensFitting(
                        entry.tokens, isTyping: entry.isTyping,
                        lines: maxLines, width: availW, settings: settings
                    )
                    result.append(trimmed)
                }
                break
            }
            used += need
            result.insert(entry, at: 0)
        }
        return result
    }

    /// 指定した行数に収まるいちばん長い末尾を返す（新しいキーほど残す）。
    /// 末尾を伸ばすほど行数は減らないので、二分探索で境目を求める。
    private static func tokensFitting(
        _ tokens: [String], isTyping: Bool, lines: Int, width: CGFloat, settings: AppSettings
    ) -> [String] {
        guard tokens.count > 1 else { return tokens }
        var lo = 1, hi = tokens.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let fits = wrappedLines(
                tokens: Array(tokens.suffix(mid)), isTyping: isTyping,
                width: width, settings: settings
            ) <= lines
            if fits { lo = mid } else { hi = mid - 1 }
        }
        return Array(tokens.suffix(lo))
    }
}

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
            // 表示領域に収まらない行は描画しない。収まらないまま描くと、
            // いちばん見せたい新しい行が切れてしまうため、古い行から落とす
            let shown = OverlayMetrics.visibleRows(displayEntries, size: geo.size, settings: settings)
            ZStack(alignment: .topLeading) {
                if settings.editMode {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundColor(.accentColor.opacity(0.8))
                        .background(Color.black.opacity(0.06).cornerRadius(12))
                }

                VStack(alignment: .leading, spacing: 8 * settings.displayScale) {
                    ForEach(settings.stackFromTop ? shown.reversed() : shown) { entry in
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

    /// 行の分け方はこの関数だけが決める。計測（sizeThatFits）と配置（placeSubviews）で
    /// 判定が食い違うと、配置時にだけ余分な折り返しが起きて後続のキーが行頭へ
    /// 重なって見える。配置時に渡される矩形はピクセル境界への丸めで報告サイズより
    /// わずかに狭いことがあるため、判定には必ず提案幅のほうを使う
    /// （キーキャップ + Windows 表記のような端数幅のラベルで起きやすい）。
    private func makeLines(
        _ subviews: Subviews, maxWidth: CGFloat
    ) -> [[(subview: LayoutSubviews.Element, size: CGSize)]] {
        var lines: [[(subview: LayoutSubviews.Element, size: CGSize)]] = []
        var line: [(subview: LayoutSubviews.Element, size: CGSize)] = []
        var lineWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if !line.isEmpty && lineWidth + spacing + size.width > maxWidth {
                lines.append(line)
                line = []
                lineWidth = 0
            }
            lineWidth += line.isEmpty ? size.width : spacing + size.width
            line.append((sub, size))
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var width: CGFloat = 0, height: CGFloat = 0
        for (i, line) in makeLines(subviews, maxWidth: proposal.width ?? .infinity).enumerated() {
            let lineWidth = line.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(line.count - 1)
            width = max(width, lineWidth)
            height += (i > 0 ? spacing : 0) + (line.map(\.size.height).max() ?? 0)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in makeLines(subviews, maxWidth: proposal.width ?? bounds.width) {
            let rowHeight = line.map(\.size.height).max() ?? 0
            var x = bounds.minX
            for item in line {
                // 行内で縦センタリングして配置する（キーキャップと「+」の高さを揃える）
                let itemY = y + (rowHeight - item.size.height) / 2
                item.subview.place(at: CGPoint(x: x, y: itemY), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += rowHeight + spacing
        }
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

    /// キーの境目に挟む文字。
    /// 「+」なしのコンビネーション表示は「⌘/Ctrl⇧/Shift」のように地続きに見えてしまうため、
    /// 細いスペース (U+2009) を入れて区切りが分かるようにする。
    /// タイピングの連結は 1 つの語として読ませたいので、区切りは入れない。
    /// いずれの場合もゼロ幅スペース (U+200B) を添えて、幅を超えたらそこで折り返せるようにする
    /// （長い連続入力は 1 語とみなされ、そのままでは折り返せず切り捨てられるため）
    private func tokenSeparator(before index: Int) -> String {
        if showPlus && !touchesOptionArrow(at: index) { return "+\u{200B}" }
        return entry.isTyping ? "\u{200B}" : "\u{2009}\u{200B}"
    }

    /// 「⌥E → ´」の矢印に接する境目かどうか。
    /// 矢印はキーどうしの組み合わせを表すものではないので、ここは「+」でつながない。
    private func touchesOptionArrow(at index: Int) -> Bool {
        guard index > 0, index < entry.tokens.count else { return false }
        return KeyFormatter.isOptionResultArrow(entry.tokens[index])
            || KeyFormatter.isOptionResultArrow(entry.tokens[index - 1])
    }

    /// トークン列を Text として連結する（クリックトークンはカーソル画像に置き換え）
    private var displayText: Text {
        var result = Text("")
        for (i, token) in entry.tokens.enumerated() {
            if i > 0 {
                result = result + Text(tokenSeparator(before: i))
            }
            if KeyFormatter.isOptionResultArrow(token) {
                result = result + Text(KeyFormatter.optionResultArrowGlyph)
            } else if let symbol = KeyFormatter.clickSymbolName(for: token) {
                result = result + Text(Image(systemName: symbol))
            } else if settings.globeOnImeKeys, KeyFormatter.isImeSwitchToken(token) {
                result = result + Text(Image(systemName: "globe")) + Text(token)
            } else {
                let drop = KeyFormatter.opticalBaselineDrop(token)
                if drop > 0 {
                    // ↩ など上に寄って見える記号は、少し下げて他の字と高さを揃える
                    result = result + Text(token).baselineOffset(-fontSize * drop)
                } else {
                    result = result + Text(token)
                }
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
                .fixedSize(horizontal: false, vertical: true)
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
                    if index > 0 && showPlus && !touchesOptionArrow(at: index) {
                        Text("+")
                            .font(.system(size: 20 * settings.displayScale, weight: .bold, design: .rounded))
                            .foregroundColor(textColor)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                    if KeyFormatter.isOptionResultArrow(token) {
                        // 併記の矢印はキーではないので、「+」と同じく素の文字で描く
                        Text(KeyFormatter.optionResultArrowGlyph)
                            .font(.system(size: 20 * settings.displayScale, weight: .bold, design: .rounded))
                            .foregroundColor(textColor)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    } else {
                        KeycapView(token: token, settings: settings)
                    }
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
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 22 * settings.displayScale)
                .padding(.vertical, 10 * settings.displayScale)
                .background(customBackground)
                .frame(maxWidth: maxWidth, alignment: .leading)
        }
    }

    /// カスタム画像を等倍で置いたときの高さ（キー表示 1 行ぶん）
    private var imageBaseHeight: CGFloat {
        fontSize * 1.2 + 20 * settings.displayScale
    }

    @ViewBuilder
    private var customBackground: some View {
        if let image = CustomBackgroundImage.scaled(
            path: settings.customImagePath, height: imageBaseHeight
        ) {
            // 9 分割（ナインパッチ）で引き伸ばす。四隅は元の比率のまま、
            // 上下の中央は横に、左右の中央は縦に、中央だけ縦横に伸びる。
            GeometryReader { geo in
                Image(nsImage: image)
                    .resizable(
                        capInsets: Self.capInsets(image: image.size, target: geo.size),
                        resizingMode: .stretch
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .opacity(settings.backgroundEnabled ? settings.backgroundOpacity : 1)
        } else {
            RoundedRectangle(cornerRadius: 12 * settings.displayScale)
                .fill(keyColor.opacity(bgOpacity))
        }
    }

    /// 画像を縦横 3 等分した位置で切る。表示領域が小さいときは、
    /// 四隅どうしが重ならないところまで切り幅を詰める（潰れ防止）。
    static func capInsets(image: CGSize, target: CGSize) -> EdgeInsets {
        let v = min(image.height / 3, max(0, target.height / 2 - 0.5))
        let h = min(image.width / 3, max(0, target.width / 2 - 0.5))
        return EdgeInsets(top: v, leading: h, bottom: v, trailing: h)
    }
}

/// カスタム背景画像の読み込みと、キー表示に合わせた寸法調整をキャッシュする。
/// 画像はキー表示 1 行ぶんの高さを基準に置き、そこから 9 分割して引き伸ばす。
enum CustomBackgroundImage {
    private static var cachedPath = ""
    private static var cachedHeight: CGFloat = 0
    private static var cached: NSImage?

    static func scaled(path: String, height: CGFloat) -> NSImage? {
        guard !path.isEmpty, height > 0 else { return nil }
        if path == cachedPath, abs(height - cachedHeight) < 0.5 { return cached }

        cachedPath = path
        cachedHeight = height
        guard let source = NSImage(contentsOfFile: path),
              source.size.width > 0, source.size.height > 0 else {
            cached = nil
            return nil
        }
        // 解像度はそのままに、表示上の寸法だけ 1 行ぶんの高さへ合わせる
        let image = (source.copy() as? NSImage) ?? source
        image.size = NSSize(
            width: source.size.width * (height / source.size.height),
            height: height
        )
        cached = image
        return image
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
            // ↩ など上に寄って見える記号は、キーキャップの中で少し下げて重心を揃える。
            // baselineOffset だとキーキャップ自体の高さが変わるので、描画位置だけずらす
            Text(token)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .offset(y: fontSize * KeyFormatter.opticalBaselineDrop(token))
        }
    }
}
