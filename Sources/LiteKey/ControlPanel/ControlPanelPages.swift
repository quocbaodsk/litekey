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
                SegmentedChoice("Kiểu gõ", selection: p.inputType, options: [
                    (.telex, "Telex"), (.vni, "VNI"), (.simpleTelex1, "Simple Telex 1"), (.simpleTelex2, "Simple Telex 2"),
                ])
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
                SegmentedChoice("Chế độ gõ", selection: p.vietnamese, options: [(true, "Tiếng Việt"), (false, "English")])
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
            // Left: typing behavior. Right: spell checking (its dependents need it on), then the ⌘ toggle.
            // Five rows a side; the longest label gets the full width below so no column has a gap.
            let spellingOff = !prefs.preferences.checkSpelling
            OptionGrid {
                GridRow {
                    SwitchRow("Đặt dấu oà, uý (thay vì òa, úy)", isOn: p.modernOrthography, icon: "a.square",
                              help: "Đặt dấu theo kiểu mới: hoà, thuý thay vì hòa, thúy.")
                    SwitchRow("Kiểm tra chính tả", isOn: p.checkSpelling, icon: "text.badge.checkmark",
                              help: "Kiểm tra từ đang gõ có đúng chính tả tiếng Việt không.")
                }
                GridRow {
                    SwitchRow("Sửa lỗi gợi ý (trình duyệt, Excel,...)", isOn: p.fixRecommendBrowser, icon: "text.cursor",
                              help: "Tránh lỗi khi ô nhập tự gợi ý từ, như thanh địa chỉ trình duyệt hay Excel.")
                    SwitchRow("Tự khôi phục phím với từ sai", isOn: p.restoreIfWrong, icon: "arrow.uturn.backward",
                              help: "Trả lại các phím đã gõ khi từ không phải tiếng Việt. Cần bật kiểm tra chính tả.")
                        .disabled(spellingOff)
                }
                GridRow {
                    SwitchRow("Viết Hoa chữ cái đầu câu", isOn: p.upperCaseFirstChar, icon: "textformat",
                              help: "Tự viết hoa chữ cái đầu tiên của mỗi câu.")
                    SwitchRow("Cho phép \"z w j f\" làm phụ âm", isOn: p.allowConsonantZFWJ, icon: "z.square",
                              help: "Coi z, w, j, f là phụ âm khi kiểm tra chính tả.")
                        .disabled(spellingOff)
                }
                GridRow {
                    SwitchRow("Chuyển chế độ thông minh", isOn: p.rememberPerApp, icon: "arrow.triangle.2.circlepath",
                              help: "Nhớ chế độ Tiếng Việt hay English riêng cho từng ứng dụng.")
                    SwitchRow("Tạm tắt chính tả bằng phím ⌃", isOn: p.tempOffSpellingWithControl, icon: "control",
                              help: "Nhấn rồi thả ⌃ để tắt kiểm tra chính tả cho từ đang gõ.")
                        .disabled(spellingOff)
                }
                GridRow {
                    SwitchRow("Cho phép bỏ dấu tự do", isOn: p.freeMark, icon: "wand.and.stars",
                              help: "Cho phép gõ dấu ở bất kỳ vị trí nào trong từ.")
                    SwitchRow("Tạm tắt LiteKey bằng phím ⌘", isOn: p.tempOffEngineWithCommand, icon: "command",
                              help: "Nhấn rồi thả ⌘ để tắt LiteKey cho từ đang gõ.")
                }
            }
            Divider()
            SwitchRow("Tắt tiếng Việt khi bộ gõ hệ thống khác tiếng Anh", isOn: p.disableOnNonEnglishInputSource,
                      icon: "globe", help: "Tự chuyển sang English khi bộ gõ của macOS không phải tiếng Anh.")
        }
        .panelCard()
    }
}

/// "Gõ tắt" page: macros, then quick consonants. Each card leads with its main switch at full width, then
/// the related options in two columns, like the other pages.
struct ShortcutsPage: View {
    @ObservedObject var model: ControlPanelModel
    @ObservedObject var prefs: PreferencesModel

    private var p: Binding<Preferences> { $prefs.preferences }

    var body: some View {
        VStack(spacing: PanelMetrics.cardSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeader("Gõ tắt")
                SwitchRow("Cho phép gõ tắt", isOn: p.useMacro, icon: "text.badge.plus",
                          help: "Thay từ gõ tắt bằng nội dung đầy đủ trong bảng gõ tắt.")
                OptionGrid {
                    GridRow {
                        SwitchRow("Gõ tắt cả khi tắt gõ tiếng Việt", isOn: p.useMacroInEnglishMode, icon: "keyboard")
                        SwitchRow("Tự động viết hoa theo phím tắt", isOn: p.autoCapsMacro, icon: "capslock",
                                  help: "Viết hoa nội dung theo cách viết hoa của từ gõ tắt.")
                    }
                }
                .disabled(!prefs.preferences.useMacro)
                Divider()
                ActionRow("Bảng gõ tắt...", icon: "list.bullet.rectangle") { model.onOpenMacros() }
            }
            .panelCard()

            VStack(alignment: .leading, spacing: 10) {
                PanelHeader("Gõ nhanh")
                SwitchRow("Gõ nhanh (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th)", isOn: p.quickTelex, icon: "hare")
                OptionGrid {
                    GridRow {
                        SwitchRow("Gõ tắt phụ âm đầu: f→ph, j→gi, w→qu", isOn: p.quickStartConsonant,
                                  icon: "text.alignleft")
                        SwitchRow("Gõ tắt phụ âm cuối: g→ng, h→nh, k→ch", isOn: p.quickEndConsonant,
                                  icon: "text.alignright")
                    }
                }
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
                OptionGrid {
                    GridRow {
                        SwitchRow("Hiện biểu tượng trên thanh Dock", isOn: p.showIconOnDock, icon: "dock.rectangle")
                        SwitchRow("Biểu tượng hiện đại trên thanh menu", isOn: p.modernMenuIcon,
                                  icon: "menubar.rectangle")
                    }
                    GridRow {
                        SwitchRow("Bật bảng này khi khởi động", isOn: p.showPanelOnStartup, icon: "macwindow")
                        SwitchRow("Khởi động cùng macOS", isOn: Binding(
                            get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }), icon: "power")
                    }
                }
            }
            .panelCard()

            VStack(alignment: .leading, spacing: 10) {
                PanelHeader("Tương thích")
                OptionGrid {
                    GridRow {
                        SwitchRow("Tương thích Telex trên các Layout khác (Dvorak, Colemak, ...)",
                                  isOn: p.layoutCompatibility, icon: "rectangle.grid.3x2")
                        SwitchRow("Sửa lỗi trên Chromium", isOn: p.fixChromiumBrowser, icon: "network",
                                  help: "Cách sửa lỗi gợi ý riêng cho Chrome, Edge, Brave... Cần bật \"Sửa lỗi gợi ý\".")
                            .disabled(!prefs.preferences.fixRecommendBrowser)
                    }
                    GridRow {
                        SwitchRow("Gửi từng phím (bật nếu bị lỗi)", isOn: p.sendKeyStepByStep, icon: "tortoise",
                                  help: "Gửi từng ký tự một, cho ứng dụng nhận sai khi gửi cả cụm.")
                        SwitchRow("Sửa lỗi Spotlight, Raycast, Alfred", isOn: p.fixOverlayLauncher,
                                  icon: "magnifyingglass",
                                  help: "Sửa chữ trong Spotlight, Raycast, Alfred qua Trợ năng thay vì gửi phím.")
                    }
                }
            }
            .panelCard()

            OptionGrid {
                GridRow {
                    ActionRow("Ứng dụng loại trừ...", icon: "nosign") { model.showExcludedApps = true }
                    ActionRow("Nhập cài đặt từ OpenKey...", icon: "square.and.arrow.down") { onImport() }
                        .disabled(!model.canImportOpenKey())
                }
            }
            .panelCard()
        }
    }
}

/// "Báo lỗi" page: placeholder until bug reporting is designed. Whatever comes next keeps the rule that
/// nothing goes over the network on its own (no data collection).
struct FeedbackPage: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "ladybug")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Sắp ra mắt")
                .font(.system(size: 15, weight: .semibold))
            Text("Tính năng báo lỗi đang được phát triển.")
                .foregroundColor(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .panelCard()
        .accessibilityElement(children: .combine)
    }
}
