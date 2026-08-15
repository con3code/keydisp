# Sample background images / サンプル背景画像

Ready-made backgrounds for the **Custom Image** key style.
「カスタム画像」スタイル用にすぐ使える背景画像です。

| File | Looks like | 用途の目安 |
|---|---|---|
| `plate-dark.png` | Dark slate plate with a soft highlight | 既定の白文字に合う万能タイプ |
| `plate-light.png` | Light card with a grey edge | 明るい画面・濃い文字色向け |
| `chalkboard.png` | Green board in a wooden frame | 授業・板書のデモ向け |
| `sticker-amber.png` | Amber sticker with a dark outline | 明るい背景でも目立たせたいとき |
| `neon-indigo.png` | Near-black panel with a glowing edge | 暗い画面・画面収録向け |

## How to use / 使い方

1. Open **Settings → Design** (設定 → デザイン)
2. Set the key style to **Custom Image**（キーのスタイルを「カスタム画像」に）
3. Press **Choose…** next to *Custom Background Image* and pick a file here
   （「カスタム背景画像」の「選択…」から選ぶ）
4. Adjust **Text Color** and **Background Opacity** to taste
   （文字色と背景の濃さを好みで調整）

Suggested text colors — 文字色の目安: white for `plate-dark` / `chalkboard` /
`neon-indigo`, and a dark color such as `#1C1C22` for `plate-light` /
`sticker-amber`.

## Making your own / 自分で作る場合

KeyDisp stretches the background as a **nine-slice**: the image is cut into
thirds on both axes, the four corners keep their proportions, the top and
bottom edges stretch only horizontally, the sides only vertically, and the
centre fills the rest. So artwork stays undistorted when a row gets wide or
wraps onto several lines.

背景画像は**9分割（ナインパッチ）**で引き伸ばされます。画像を縦横 3 等分し、
四隅は比率を保ったまま、上下の中央は横に、左右の中央は縦に、中央は縦横に伸びます。

To keep an image from breaking up — 崩れない画像にするコツ:

- Keep corner decoration inside the corner third
  （角の装飾は角の 1/3 以内に収める。角丸なら半径をサイズの 1/3 未満に）
- Make each edge uniform along the direction it stretches — a vertical
  gradient is fine, a horizontal one on the top edge is not
  （伸びる方向に模様を変化させない。縦グラデーションは可、上辺の横グラデーションは不可）
- Square images around 300×300 px work well
  （300×300px 程度の正方形が扱いやすい）

These samples were generated with a script; the source is in the repository
history. / これらは生成スクリプトで作成しています。

© 2026 con3code — same [MIT License](../../LICENSE) as the app.
