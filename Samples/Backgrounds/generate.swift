// KeyDisp カスタム背景のサンプル画像を生成する。
// 9 分割（各辺 1/3）で伸ばしても崩れないよう、装飾は角の 1/3 以内に収め、
// 辺は伸びる方向に対して一様（縦グラデーションのみ）にしている。
import AppKit

let S: CGFloat = 300          // 画像サイズ（1/3 = 100px が伸縮の境界）
let inset: CGFloat = 12       // 影のための余白
let radius: CGFloat = 70      // 角丸半径（角の 1/3 = 100px に収まる）

func makeImage(_ name: String, _ draw: (NSRect) -> Void) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2))
    NSGraphicsContext.restoreGraphicsState()
    let url = URL(fileURLWithPath: "/Users/rin/Dev/keydisp/Samples/Backgrounds/\(name).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(name).png")
}

func rounded(_ r: NSRect) -> NSBezierPath {
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
}

func shadow(_ blur: CGFloat, _ alpha: CGFloat, dy: CGFloat = -3) -> NSShadow {
    let s = NSShadow()
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: dy)
    s.shadowColor = NSColor(white: 0, alpha: alpha)
    return s
}

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

// 1. ダークプレート: 白文字向けの落ち着いた土台
makeImage("plate-dark") { r in
    NSGraphicsContext.current?.saveGraphicsState()
    shadow(10, 0.45).set()
    c(28, 28, 36, 0.94).setFill()
    rounded(r).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(starting: c(255, 255, 255, 0.14), ending: c(255, 255, 255, 0))!
        .draw(in: rounded(r), angle: -90)
    c(255, 255, 255, 0.22).setStroke()
    let s = rounded(r.insetBy(dx: 1.5, dy: 1.5)); s.lineWidth = 3; s.stroke()
}

// 2. ライトカード: 明るい画面・濃い文字色向け
makeImage("plate-light") { r in
    NSGraphicsContext.current?.saveGraphicsState()
    shadow(12, 0.28).set()
    c(248, 248, 252, 0.96).setFill()
    rounded(r).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(starting: c(255, 255, 255, 1), ending: c(226, 226, 236, 1))!
        .draw(in: rounded(r), angle: -90)
    c(150, 148, 168, 0.55).setStroke()
    let s = rounded(r.insetBy(dx: 1.5, dy: 1.5)); s.lineWidth = 3; s.stroke()
}

// 3. 黒板: 授業向け。白いチョーク色の文字が映える
makeImage("chalkboard") { r in
    NSGraphicsContext.current?.saveGraphicsState()
    shadow(10, 0.5).set()
    c(38, 62, 52).setFill()
    rounded(r).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(starting: c(255, 255, 255, 0.07), ending: c(0, 0, 0, 0.10))!
        .draw(in: rounded(r), angle: -90)
    // 木枠風の二重線
    c(196, 160, 104, 0.95).setStroke()
    let outer = rounded(r.insetBy(dx: 3, dy: 3)); outer.lineWidth = 6; outer.stroke()
    c(255, 255, 255, 0.30).setStroke()
    let inner = NSBezierPath(roundedRect: r.insetBy(dx: 14, dy: 14),
                             xRadius: radius - 12, yRadius: radius - 12)
    inner.lineWidth = 2; inner.stroke()
}

// 4. 付箋（アンバー）: 明るい背景でもよく目立つ
makeImage("sticker-amber") { r in
    NSGraphicsContext.current?.saveGraphicsState()
    shadow(10, 0.35).set()
    c(255, 179, 0).setFill()
    rounded(r).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(starting: c(255, 206, 92, 1), ending: c(240, 158, 0, 1))!
        .draw(in: rounded(r), angle: -90)
    c(120, 74, 0, 0.85).setStroke()
    let s = rounded(r.insetBy(dx: 2, dy: 2)); s.lineWidth = 4; s.stroke()
}

// 5. ネオン（インディゴ）: 暗い画面・収録向け
makeImage("neon-indigo") { r in
    NSGraphicsContext.current?.saveGraphicsState()
    shadow(14, 0.55).set()
    c(16, 14, 26, 0.95).setFill()
    rounded(r).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    // 発光する縁（外側の淡い線 → 内側の明るい線）
    for (w, a) in [(CGFloat(9), CGFloat(0.18)), (6, 0.30), (3, 0.95)] {
        c(158, 144, 255, a).setStroke()
        let s = rounded(r.insetBy(dx: 3, dy: 3)); s.lineWidth = w; s.stroke()
    }
    NSGradient(starting: c(158, 144, 255, 0.12), ending: c(158, 144, 255, 0))!
        .draw(in: rounded(r.insetBy(dx: 4, dy: 4)), angle: -90)
}
