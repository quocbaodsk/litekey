import LiteKeyCore
import LiteKeyEngine
import SwiftUI

/// "Bộ gõ" page: input method, hotkey and mode on top, typing options below
struct TypingPage: View {
    @ObservedObject var model: ControlPanelModel
    @ObservedObject var prefs: PreferencesModel

    private var p: Binding<Preferences> { $prefs.preferences }

    var body: some View {
        VStack(spacing: PanelMetrics.cardSpacing) {
            controlCard
            optionsCard
        }
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
            PanelRow("Kiểu gõ") {
                Picker("Kiểu gõ", selection: p.inputType) {
                    Text("Telex").tag(InputType.telex)
                    Text("VNI").tag(InputType.vni)
                    Text("Simple Telex 1").tag(InputType.simpleTelex1)
                    Text("Simple Telex 2").tag(InputType.simpleTelex2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
            PanelRow("Phím chuyển") {
                HStack(spacing: 6) {
                    modifierToggle("⌃", .control)
                    modifierToggle("⌥", .option)
                    modifierToggle("⌘", .command)
                    modifierToggle("⇧", .shift)
                    HotkeyRecorder(hotkey: p.hotkey, onRecording: model.onRecordingHotkey)
                        .frame(width: 64, height: 22)
                        .padding(.leading, 4)
                }
                Spacer(minLength: 12)
                SwitchRow("Kêu beep", isOn: p.beepOnSwitch, fill: false)
            }
            if !prefs.preferences.hotkey.isUsable {
                // Old or imported settings: fewer than two keys is not usable
                Text("Phím chuyển cần ít nhất 2 phím, trong đó có một phím ⌃ ⌥ ⌘ ⇧")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.leading, PanelMetrics.labelWidth + 12)
            }
            PanelRow("Chế độ gõ") {
                Picker("Chế độ gõ", selection: p.vietnamese) {
                    Text("Tiếng Việt").tag(true)
                    Text("English").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
        }
        .panelCard()
    }

    private func modifierToggle(_ symbol: String, _ flag: ModifierFlags) -> some View {
        let hotkey = prefs.preferences.hotkey
        let isOn = hotkey.modifiers.contains(flag)
        return KeycapToggle(symbol: symbol, isOn: Binding(
            get: { prefs.preferences.hotkey.modifiers.contains(flag) },
            set: { on in
                var hotkey = prefs.preferences.hotkey
                if on { hotkey.modifiers.insert(flag) } else if hotkey.canRemove(flag) { hotkey.modifiers.remove(flag) }
                prefs.preferences.hotkey = hotkey
            }))
            // A hotkey keeps at least two keys (`Hotkey.minimumKeys`)
            .disabled(isOn && !hotkey.canRemove(flag))
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader("Tuỳ chọn gõ")
            TwoColumns {
                SwitchRow("Đặt dấu oà, uý (thay vì òa, úy)", isOn: p.modernOrthography, icon: "a.square",
                          help: "Đặt dấu theo kiểu mới: hoà, thuý thay vì hòa, thúy.")
                SwitchRow("Sửa lỗi gợi ý (trình duyệt, Excel,...)", isOn: p.fixRecommendBrowser, icon: "text.cursor",
                          help: "Tránh lỗi khi ô nhập tự gợi ý từ, như thanh địa chỉ trình duyệt hay Excel.")
                SwitchRow("Viết Hoa chữ cái đầu câu", isOn: p.upperCaseFirstChar, icon: "textformat",
                          help: "Tự viết hoa chữ cái đầu tiên của mỗi câu.")
                SwitchRow("Chuyển chế độ thông minh", isOn: p.rememberPerApp, icon: "arrow.triangle.2.circlepath",
                          help: "Nhớ chế độ Tiếng Việt hay English riêng cho từng ứng dụng.")
                SwitchRow("Cho phép bỏ dấu tự do", isOn: p.freeMark, icon: "wand.and.stars",
                          help: "Cho phép gõ dấu ở bất kỳ vị trí nào trong từ.")
                SwitchRow("Tắt tiếng Việt khi bộ gõ hệ thống khác tiếng Anh", isOn: p.disableOnNonEnglishInputSource,
                          icon: "globe", help: "Tự chuyển sang English khi bộ gõ của macOS không phải tiếng Anh.")
            } right: {
                SwitchRow("Kiểm tra chính tả", isOn: p.checkSpelling, icon: "text.badge.checkmark",
                          help: "Kiểm tra từ đang gõ có đúng chính tả tiếng Việt không.")
                Group {
                    SwitchRow("Tự khôi phục phím với từ sai", isOn: p.restoreIfWrong, icon: "arrow.uturn.backward",
                              help: "Trả lại các phím đã gõ khi từ không phải tiếng Việt. Cần bật kiểm tra chính tả.")
                    SwitchRow("Cho phép \"z w j f\" làm phụ âm", isOn: p.allowConsonantZFWJ, icon: "z.square",
                              help: "Coi z, w, j, f là phụ âm khi kiểm tra chính tả.")
                    SwitchRow("Tạm tắt chính tả bằng phím ⌃", isOn: p.tempOffSpellingWithControl, icon: "control",
                              help: "Nhấn rồi thả ⌃ để tắt kiểm tra chính tả cho từ đang gõ.")
                }
                .disabled(!prefs.preferences.checkSpelling)
                SwitchRow("Tạm tắt LiteKey bằng phím ⌘", isOn: p.tempOffEngineWithCommand, icon: "command",
                          help: "Nhấn rồi thả ⌘ để tắt LiteKey cho từ đang gõ.")
            }
        }
        .panelCard()
    }
}

/// "Gõ tắt" page: macros, then quick consonants
struct ShortcutsPage: View {
    @ObservedObject var model: ControlPanelModel
    @ObservedObject var prefs: PreferencesModel

    private var p: Binding<Preferences> { $prefs.preferences }

    var body: some View {
        VStack(spacing: PanelMetrics.cardSpacing) {
            VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
                PanelHeader("Gõ tắt")
                SwitchRow("Cho phép gõ tắt", isOn: p.useMacro, icon: "text.badge.plus",
                          help: "Thay từ gõ tắt bằng nội dung đầy đủ trong bảng gõ tắt.")
                Group {
                    SwitchRow("Gõ tắt cả khi tắt gõ tiếng Việt", isOn: p.useMacroInEnglishMode, icon: "keyboard")
                    SwitchRow("Tự động viết hoa theo phím tắt", isOn: p.autoCapsMacro, icon: "capslock",
                              help: "Viết hoa nội dung theo cách viết hoa của từ gõ tắt.")
                }
                .disabled(!prefs.preferences.useMacro)
                Divider()
                ActionRow("Bảng gõ tắt...", icon: "list.bullet.rectangle") { model.onOpenMacros() }
            }
            .panelCard()

            VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
                PanelHeader("Gõ nhanh")
                SwitchRow("Gõ nhanh (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th)", isOn: p.quickTelex, icon: "hare")
                SwitchRow("Gõ tắt phụ âm đầu: f→ph, j→gi, w→qu", isOn: p.quickStartConsonant, icon: "text.alignleft")
                SwitchRow("Gõ tắt phụ âm cuối: g→ng, h→nh, k→ch", isOn: p.quickEndConsonant, icon: "text.alignright")
            }
            .panelCard()
        }
    }
}

/// "Hệ thống" page: app behavior on the left, compatibility fixes on the right, then the list actions
struct SystemPage: View {
    @ObservedObject var model: ControlPanelModel
    @ObservedObject var prefs: PreferencesModel
    var onImport: () -> Void

    private var p: Binding<Preferences> { $prefs.preferences }

    var body: some View {
        VStack(spacing: PanelMetrics.cardSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeader("Ứng dụng")
                TwoColumns {
                    SwitchRow("Hiện biểu tượng trên thanh Dock", isOn: p.showIconOnDock, icon: "dock.rectangle")
                    SwitchRow("Bật bảng này khi khởi động", isOn: p.showPanelOnStartup, icon: "macwindow")
                } right: {
                    SwitchRow("Biểu tượng hiện đại trên thanh menu", isOn: p.modernMenuIcon, icon: "menubar.rectangle")
                    SwitchRow("Khởi động cùng macOS", isOn: Binding(
                        get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }), icon: "power")
                }
            }
            .panelCard()

            VStack(alignment: .leading, spacing: 10) {
                PanelHeader("Tương thích")
                TwoColumns {
                    SwitchRow("Tương thích Telex trên các Layout khác (Dvorak, Colemak, ...)",
                              isOn: p.layoutCompatibility, icon: "rectangle.grid.3x2")
                    SwitchRow("Gửi từng phím (bật nếu bị lỗi)", isOn: p.sendKeyStepByStep, icon: "tortoise",
                              help: "Gửi từng ký tự một, cho ứng dụng nhận sai khi gửi cả cụm.")
                } right: {
                    SwitchRow("Sửa lỗi trên Chromium", isOn: p.fixChromiumBrowser, icon: "network",
                              help: "Cách sửa lỗi gợi ý riêng cho Chrome, Edge, Brave... Cần bật \"Sửa lỗi gợi ý\".")
                        .disabled(!prefs.preferences.fixRecommendBrowser)
                    SwitchRow("Sửa lỗi Spotlight, Raycast, Alfred", isOn: p.fixOverlayLauncher, icon: "magnifyingglass",
                              help: "Sửa chữ trong Spotlight, Raycast, Alfred qua Trợ năng thay vì gửi phím.")
                }
            }
            .panelCard()

            TwoColumns {
                ActionRow("Ứng dụng loại trừ...", icon: "nosign") { model.showExcludedApps = true }
            } right: {
                ActionRow("Nhập cài đặt từ OpenKey...", icon: "square.and.arrow.down") { onImport() }
                    .disabled(!model.canImportOpenKey())
            }
            .panelCard()
        }
    }
}
