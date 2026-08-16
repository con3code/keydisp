import AppKit
import Carbon
import SwiftUI


/// 設定画面のサイドバー項目
enum SettingsPane: String, CaseIterable, Identifiable {
    case display, keyLabels, design, mouse, general, permissions, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .display:     return L("表示", "Display")
        case .keyLabels:   return L("キー表記", "Key Labels")
        case .design:      return L("デザイン", "Design")
        case .mouse:       return L("マウス", "Mouse")
        case .general:     return L("一般", "General")
        case .permissions: return L("権限", "Permissions")
        case .about:       return L("KeyDisp について", "About KeyDisp")
        }
    }

    var symbol: String {
        switch self {
        case .display:     return "macwindow"
        case .keyLabels:   return "keyboard"
        case .design:      return "paintpalette.fill"
        case .mouse:       return "computermouse.fill"
        case .general:     return "gearshape.fill"
        case .permissions: return "lock.shield.fill"
        case .about:       return "info"
        }
    }

    var color: Color {
        switch self {
        case .display:     return .blue
        case .keyLabels:   return .indigo
        case .design:      return .orange
        case .mouse:       return .pink
        case .general:     return .gray
        case .permissions: return .green
        case .about:       return .teal
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var inputMonitoringOK = Permissions.inputMonitoringGranted
    @State private var pane: SettingsPane = .display

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        // システム設定と同じ、左サイドバーで切り替える形式
        NavigationSplitView {
            List(selection: $pane) {
                ForEach(SettingsPane.allCases) { pane in
                    sidebarRow(pane).tag(pane)
                }
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            if pane == .about {
                AboutView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    switch pane {
                    case .display:     displaySection
                    case .keyLabels:   keyLabelsSection
                    case .design:      designSection
                    case .mouse:       mouseSection
                    case .general:
                        shortcutSection
                        generalSection
                    case .permissions, .about: permissionsSection
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(width: 730, height: 560)
        .onReceive(timer) { _ in
            inputMonitoringOK = Permissions.inputMonitoringGranted
        }
    }

    /// サイドバーの 1 行（システム設定風の角丸カラーアイコン + 名前）
    private func sidebarRow(_ pane: SettingsPane) -> some View {
        Label {
            Text(pane.title)
        } icon: {
            Image(systemName: pane.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(pane.color))
        }
    }

    @ViewBuilder private var displaySection: some View {
            Section {
                Toggle(L("すべてのキー入力を表示", "Show all key input"), isOn: $settings.showAllKeys)
                Text(L("オフのときは、修飾キー付きのコンビネーションと特殊キー（↩ ⇥ ⎋ 矢印など）だけを表示します。オンにすると通常のタイピング（英数字など）も表示されます。",
                       "When off, only combinations with modifier keys and special keys (↩ ⇥ ⎋ arrows, etc.) are shown. When on, ordinary typing (letters and numbers) is also displayed."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle(L("同じキーの連続入力を ×n でまとめる", "Group repeated keys as ×n"), isOn: $settings.countRepeats)
                Text(L("同じコンビネーションの連続押しや長押し（キーリピート）を、新しい行を増やさず「⌘V ×3」のような回数表示にまとめます。",
                       "Repeated presses or held key repeats of the same combination are shown as a count like \"⌘V ×3\" instead of new rows."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle(L("修飾キーを離すたびに履歴を残す", "Keep a row each time a modifier is released"), isOn: $settings.stepModifierRelease)
                Text(L("修飾キーの一部を離して残りを「区切りの判定時間」以上押し続けたときの動きが変わります。オンなら、そこまでの組み合わせを履歴として残し、押している組み合わせを新しい行に出します（⇧⌘ → ⇧）。オフなら行を増やさず、その行が押している組み合わせだけの表示に変わります。どちらもそれより早く離しきった場合は、押した組み合わせ全体が 1 行として残ります。",
                       "Changes what happens when you release part of a combination and hold the rest for longer than the hold threshold. On: the combination so far stays as history and the keys still held start a new row (⇧⌘ → ⇧). Off: no row is added — the row simply narrows to the keys still held. Either way, releasing everything sooner leaves the whole combination as one row."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                sliderRow(L("区切りの判定時間", "Hold Threshold"), value: $settings.holdJudgeDelay,
                          in: 0.2...2.0, format: L("%.1f 秒", "%.1f s"))
                Text(L("⇧⌘ のように複数のキーを押して片方だけ離したとき、残りをこの時間だけ押し続けると「意図して押している」と判断し、上の設定に従って表示が変わります。これより早く離しきった場合は、押した組み合わせ全体（⇧⌘）が 1 行として残ります。短くすると反応が早くなり、長くすると組み合わせがまとまりやすくなります。",
                       "When you hold several keys — ⇧⌘, say — and let one go, keeping the rest down for this long counts as deliberate, and the display changes as the setting above describes. Release everything sooner and the whole combination (⇧⌘) stays as one row. Shorten it for a quicker reaction, lengthen it to keep combinations together."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                sliderRow(L("サイズ", "Size"), value: $settings.displayScale, in: 0.5...5.0, format: "×%.1f")
                sliderRow(L("表示の持続時間", "Hold Duration"), value: $settings.holdDuration, in: 0...5, format: L("%.1f 秒", "%.1f s"))
                sliderRow(L("フェードアウトの長さ", "Fade-out Duration"), value: $settings.fadeDuration, in: 0.1...4, format: L("%.1f 秒", "%.1f s"))
                sliderRow(L("表示の行数", "Display Rows"), value: $settings.maxRows, in: 1...8, step: 1, format: L("%.0f 行", "%.0f"))
                Toggle(L("新しい入力を上に表示（ぶら下がり式）", "Show newest at the top (hang-down style)"), isOn: $settings.stackFromTop)
                Text(L("オフのときは下端を基準に新しい行が下に入り、古い行が上へ積み上がります。オンにすると上端が基準になり、新しい行が上に入って古い行が下へ押し下げられます。",
                       "When off, rows stack upward from the bottom edge (newest at the bottom). When on, rows hang from the top edge (newest at the top, older rows pushed down)."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(L("表示領域の位置と大きさは、メニューバーの「表示編集モード」でドラッグして変更できます。",
                       "Move and resize the display area by dragging it in \"Edit Display Mode\" from the menu bar."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle(L("画面の上端にカーソルを置いている間は履歴を消さない",
                         "Keep history while the cursor is at the top edge of the screen"),
                       isOn: $settings.topEdgeFreeze)
                Text(L("カーソルを画面の上端へ持っていくと、その間はフェードアウトが止まり、表示中の履歴がそのまま残ります。離すと通常どおり消えていきます。",
                       "Park the cursor at the top edge to pause the fade-out and keep the rows on screen. Move away and they resume fading."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(L("画面の下端にカーソルを置いている間はキー表示を隠す",
                         "Hide key display while the cursor is at the bottom edge of the screen"),
                       isOn: $settings.hotCornerHide)
                Text(L("いずれかの画面の底辺（下端 10px 以内）にカーソルがある間だけ、キー表示を一時的に非表示にし、その間の新しいキー入力も表示しません。",
                       "Temporarily hides the key display while the cursor stays within 10 px of the bottom edge of any screen. New key input during that time is not shown either."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
    }

    @ViewBuilder private var keyLabelsSection: some View {
            Section {
                Toggle(L("英字の大文字/小文字を区別して表示", "Distinguish upper/lower case letters"), isOn: $settings.distinguishCase)
                Text(L("オフのときは英字をすべて大文字で表示します。オンにするとタイピング表示が実際の入力どおり（Shift・Caps Lock を反映した大文字/小文字）になります。コンビネーション（⌘A など）は常に大文字表記です。",
                       "When off, letters are always shown uppercase. When on, typed letters appear exactly as entered (reflecting Shift and Caps Lock). Combinations (⌘A etc.) always use uppercase."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker(L("矢印キーのまとめ方", "Arrow Keys"), selection: $settings.arrowGrouping) {
                    ForEach(ArrowGrouping.allCases) { g in
                        Text(g.label).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                Text(L("「同時押しのみ」は →↓ のように 2 つ以上を同時に押しているときだけ 1 行にまとめます（斜め移動の実演向け）。「連続入力もまとめる」は続けて押した矢印も同じ行に足していきます（→→↓ のようなカーソル移動向け）。",
                       "\"Held together\" groups arrows only while two or more are down at once (for diagonal movement). \"Also consecutive\" keeps adding arrows pressed one after another to the same row (for cursor movement)."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(L("修飾キーを押した順に表示", "Show modifiers in the order pressed"), isOn: $settings.modifierPressOrder)
                Text(L("オフのときは説明書などで使われる標準的な並び（⌃ ⌥ ⇧ ⌘）で表示します。オンにすると実際に押した順で並ぶので、操作の手順を見せたいときに使えます。",
                       "When off, modifiers appear in the conventional order used in documentation (⌃ ⌥ ⇧ ⌘). When on, they appear in the order you actually pressed them — useful for showing the sequence of an operation."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(L("キーの間に「+」を表示", "Separate keys with \"+\""), isOn: $settings.plusSeparator)
                Text(L("コンビネーションを Ctrl+Shift+S のように区切って表示します（タイピングの連続表示には付きません）。",
                       "Shows combinations like Ctrl+Shift+S (not applied to continuous typing)."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker(L("表記スタイル", "Label Style"), selection: $settings.osLabelStyle) {
                    ForEach(OSLabelStyle.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                Text(L("Windows 表記はショートカット互換の対応で表示します: ⌘/⌃ → Ctrl、⌥ → Alt、↩ → Enter、⌫ → BackSpace、英数 → 無変換、かな → 変換 など。併存表示では「⌘/Ctrl」のように両方を表示します。",
                       "Windows labels use shortcut-equivalent mapping: ⌘/⌃ → Ctrl, ⌥ → Alt, ↩ → Enter, ⌫ → BackSpace, etc. Combined mode shows both, e.g. \"⌘/Ctrl\"."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(L("⌥ で入力される記号を併記", "Show the symbol ⌥ produces"), isOn: $settings.showOptionSymbols)
                Text(L("⌥ と文字キーの組み合わせで実際に入力される記号を「⌥E → ´」のように併記します。アクセント記号（デッドキー）も記号そのものを表示します。",
                       "Shows what the combination actually types, as in \"⌥E → ´\". Accent marks (dead keys) are shown as the mark itself."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(L("入力切替キーに 🌐 を付ける", "Add 🌐 to input-switch keys"), isOn: $settings.globeOnImeKeys)
                Text(L("英数/かな（ABC/あいう）キーの表示に地球儀マークを付けて、通常の文字入力と区別しやすくします。キーボードに地球儀キーが別にあって紛らわしい場合はオフにしてください。",
                       "Adds a globe mark to the 英数/かな (ABC/あいう) key display to distinguish them from ordinary typing. Turn off if it is confusing because your keyboard has a separate Globe key."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(L("「英数/かな」を「ABC/あいう」と表示", "Show 英数/かな as ABC/あいう"), isOn: $settings.jisABCLabels)
                Text(L("新しい JIS 配列キーボードの刻印（ABC / あいう）に合わせた表記です。",
                       "Matches the key legends (ABC / あいう) on newer JIS keyboards."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(L("かな入力（JIS かな配列）をひらがなで表示", "Show kana input as hiragana (JIS kana layout)"), isOn: $settings.kanaDisplay)
                Text(L("かな入力をお使いの場合にオンにしてください。日本語入力モード中のタイピング表示が JIS かな配列のひらがな・記号（ち、と、し… や 「」、。など）になり、英数モードに切り替えるとアルファベット表示に戻ります。ローマ字入力をお使いの場合はオフのままにしてください（入力方式は自動判別できないため）。",
                       "Turn this on if you use kana input. While in Japanese input mode, typed keys are shown as JIS kana layout hiragana and symbols; switching to ABC mode returns to letters. Leave it off if you use romaji input (the input style cannot be detected automatically)."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
    }

    @ViewBuilder private var designSection: some View {
            Section {
                Picker(L("キーのスタイル", "Key Style"), selection: $settings.style) {
                    ForEach(KeyStyle.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                ColorPicker(L("文字色", "Text Color"), selection: settings.colorBinding(\.textColorHex))
                ColorPicker(L("キー / 背景色", "Key / Background Color"), selection: settings.colorBinding(\.keyColorHex))
                Toggle(L("背景を表示", "Show Background"), isOn: $settings.backgroundEnabled)
                sliderRow(L("背景の濃さ", "Background Opacity"), value: $settings.backgroundOpacity, in: 0...1, format: "%.0f%%", multiplier: 100)
                    .disabled(!settings.backgroundEnabled)

                HStack {
                    Text(L("カスタム背景画像", "Custom Background Image"))
                    Spacer()
                    Text(settings.customImagePath.isEmpty
                         ? L("未設定", "None")
                         : (settings.customImagePath as NSString).lastPathComponent)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 180, alignment: .trailing)
                    Button(L("選択…", "Choose…")) { chooseImage() }
                    if !settings.customImagePath.isEmpty {
                        Button(L("クリア", "Clear")) { settings.customImagePath = "" }
                    }
                }
                Text(L("カスタム画像は「カスタム画像」スタイル選択時に、キー表示の背景として使われます。",
                       "The custom image is used as the key display background when the \"Custom Image\" style is selected."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
    }

    @ViewBuilder private var mouseSection: some View {
            Section {
                Toggle(L("クリック / ドラッグをカーソル位置に表示", "Show clicks / drags at the cursor"), isOn: $settings.mouseHighlight)
                ColorPicker(L("ハイライトの色", "Highlight Color"), selection: settings.colorBinding(\.mouseColorHex))
                    .disabled(!settings.mouseHighlight)
                sliderRow(L("ハイライトの大きさ", "Highlight Size"), value: $settings.mouseHighlightSize, in: 30...120, format: "%.0f px")
                    .disabled(!settings.mouseHighlight)
                Text(L("クリックした瞬間と、ボタンを押している間（ドラッグ中）に、カーソルの位置へ円を表示します。左クリックは塗りつぶし、右クリックは二重リングで区別されます。",
                       "Shows a circle at the cursor when you click and while a button is held (dragging). Left click is filled; right click is a double ring."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(L("大きいマウスカーソル", "Large mouse pointer"), isOn: $settings.bigCursor)
                ColorPicker(L("カーソルの色", "Pointer Color"), selection: settings.colorBinding(\.bigCursorColorHex))
                    .disabled(!settings.bigCursor)
                sliderRow(L("カーソルの大きさ", "Pointer Size"), value: $settings.bigCursorSize, in: 32...160, format: "%.0f px")
                    .disabled(!settings.bigCursor)
                Text(L("マウスカーソルに追従する大きなポインタを重ねて表示します。macOS のポインタ自体を拡大することはアプリからはできないため、標準のカーソルは先端に重なったまま残ります。システム側で本当に大きくしたい場合は、システム設定 › アクセシビリティ › ディスプレイ › ポインタのサイズ で変更できます。",
                       "Draws a large pointer that follows the cursor. The app cannot enlarge the macOS pointer itself, so the standard cursor stays visible at the tip. To enlarge the real pointer, use System Settings › Accessibility › Display › Pointer size."))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(L("修飾キー + クリックをキー表示に出す", "Show modifier + click in the key display"), isOn: $settings.showClickInKeyDisplay)
                Toggle(L("押しっぱなしの文字キー + クリックも出す", "Include held letter keys with clicks"), isOn: $settings.showKeyClickCombo)
                    .disabled(!settings.showClickInKeyDisplay)
                Text(L("⌘ や ⇧ などを押しながらクリックすると、キー表示に「⌘ + カーソルマーク」の行が出て、押している間は表示され続けます。下をオンにすると、A などの文字キーを押しっぱなしにしたままのクリックも同じように表示します（通常のタイピング中のクリックには反応しません）。",
                       "Clicking while holding ⌘, ⇧, etc. adds a row like \"⌘ + cursor mark\" to the key display, and it stays while the button is held. Turn on the second option to do the same for letter keys you are holding down (clicking while typing normally is unaffected)."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
    }

    @ViewBuilder private var shortcutSection: some View {
            Section(L("ショートカット", "Shortcut")) {
                HStack {
                    Text(L("表示 / 非表示の切替え", "Toggle Show / Hide"))
                    Spacer()
                    ShortcutRecorderView(settings: settings)
                }
            }
    }

    @ViewBuilder private var generalSection: some View {
            Section(L("一般", "General")) {
                Picker(L("言語", "Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                Toggle(L("ログイン時に起動", "Launch at Login"), isOn: $settings.launchAtLogin)
                Toggle(L("メニューバーにアイコンを表示", "Show Menu Bar Icon"), isOn: $settings.showMenuBarIcon)
                Toggle(L("Dock にアイコンを表示", "Show Dock Icon"), isOn: $settings.showDockIcon)
                Text(L("メニューバーと Dock の両方を非表示にはできません。表示を戻すには Finder でアプリをもう一度開くと設定画面が開きます。",
                       "The menu bar icon and Dock icon cannot both be hidden. To get back, open the app again in Finder and this settings window will appear."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
    }

    @ViewBuilder private var permissionsSection: some View {
            Section {
                permissionRow(L("入力監視", "Input Monitoring"), granted: inputMonitoringOK) {
                    // 再リクエストすることで、一覧から削除された場合でも
                    // システム設定のリストに KeyDisp が再追加される
                    Permissions.requestInputMonitoring()
                    Permissions.openInputMonitoringSettings()
                }
                HStack {
                    Text(L("動作がおかしいとき", "If it doesn't seem to work"))
                    Spacer()
                    Button(L("再確認", "Re-check")) {
                        inputMonitoringOK = Permissions.inputMonitoringGranted
                        NotificationCenter.default.post(name: .keyDispRecheckPermissions, object: nil)
                    }
                }
                Text(L("キー監視には「入力監視」の権限が必要です。\n「再確認」は権限の状態を確認し直し、キー監視を再起動します。「許可済み」と表示されていてもキーが表示されない場合（再インストール後に古い権限項目が残っている場合など）にお試しください。それでも直らない場合は、システム設定の一覧から KeyDisp を削除（−ボタン）し、上のボタンで再追加してください。",
                       "Key capture requires the Input Monitoring permission.\n\"Re-check\" verifies the permission state and restarts key capture. Try it when keys are not displayed even though the permission shows as granted (e.g. a stale permission entry after reinstalling). If that doesn't help, remove KeyDisp from the list in System Settings (− button) and re-add it with the button above."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
    }


    private func sliderRow(
        _ label: String, value: Binding<Double>, in range: ClosedRange<Double>,
        step: Double? = nil, format: String, multiplier: Double = 1
    ) -> some View {
        HStack {
            Text(label)
            if let step {
                Slider(value: value, in: range, step: step)
            } else {
                Slider(value: value, in: range)
            }
            Text(String(format: format, value.wrappedValue * multiplier))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func permissionRow(_ name: String, granted: Bool, open: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(granted ? .green : .orange)
            Text(name)
            Spacer()
            if !granted {
                Button(L("システム設定を開く", "Open System Settings")) { open() }
            } else {
                Text(L("許可済み", "Granted")).foregroundColor(.secondary)
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            // サンドボックスでは再起動後もファイルへアクセスできるよう、ブックマークで保存する
            settings.setCustomImage(url: url)
        }
    }
}

/// ホットキー録音ボタン
struct ShortcutRecorderView: View {
    @ObservedObject var settings: AppSettings
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stopRecording() : startRecording()
        } label: {
            Text(recording
                 ? L("キーを押してください… (esc でキャンセル)", "Press keys… (esc to cancel)")
                 : KeyFormatter.shortcutDescription(
                     keyCode: settings.hotKeyKeyCode,
                     carbonModifiers: settings.hotKeyModifiers))
                .frame(minWidth: 120)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { stopRecording() }
            if event.keyCode == 53 { return nil } // esc = キャンセル
            var carbon = 0
            let flags = event.modifierFlags
            if flags.contains(.command) { carbon |= cmdKey }
            if flags.contains(.option) { carbon |= optionKey }
            if flags.contains(.control) { carbon |= controlKey }
            if flags.contains(.shift) { carbon |= shiftKey }
            // 修飾キーなしのショートカットは誤動作しやすいので不可
            guard carbon & ~shiftKey != 0 else {
                NSSound.beep()
                return nil
            }
            settings.hotKeyKeyCode = Int(event.keyCode)
            settings.hotKeyModifiers = carbon
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
