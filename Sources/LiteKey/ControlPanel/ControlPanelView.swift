import AppKit
import LiteKeyCore
import LiteKeyEngine
import LiteKeyPlatform
import SwiftUI

/// Control Panel state and actions (provided by AppDelegate).
final class ControlPanelModel: ObservableObject {
    enum Tab: Int, CaseIterable {
        case typing, shortcuts, system, info

        var title: String {
            switch self {
            case .typing: return "Bộ gõ"
            case .shortcuts: return "Gõ tắt"
            case .system: return "Hệ thống"
            case .info: return "Thông tin"
            }
        }
    }

    @Published var tab: Tab = .typing
    @Published var hasPermission = false
    @Published var launchAtLogin = LoginItem.isEnabled
    /// Excluded apps sheet; also opened from the menu bar ("Quản lý...")
    @Published var showExcludedApps = false

    let preferences: PreferencesModel
    var onRetryPermission: () -> Void = {}
    var onRecordingHotkey: (Bool) -> Void = { _ in }
    var onQuit: () -> Void = {}
    var onClose: () -> Void = {}
    var canImportOpenKey: () -> Bool = { false }
    var onImportOpenKey: () -> Void = {}
    var onOpenMacros: () -> Void = {}

    init(preferences: PreferencesModel) {
        self.preferences = preferences
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            NSSound.beep()
        }
        launchAtLogin = LoginItem.isEnabled
    }
}

/// Control Panel: control card on top, tab bar over the tab card (typing, shortcuts, system, info), and
/// Quit / Defaults / OK buttons. Every row puts its label on the left and its control on the right.
struct ControlPanelView: View {
    @ObservedObject var model: ControlPanelModel
    @ObservedObject var prefs: PreferencesModel
    @State private var confirmDefaults = false
    @State private var confirmImport = false

    /// Fixed so switching tabs never resizes the window
    private static let tabHeight: CGFloat = 208

    init(model: ControlPanelModel) {
        _model = ObservedObject(wrappedValue: model)
        _prefs = ObservedObject(wrappedValue: model.preferences)
    }

    private var p: Binding<Preferences> { $prefs.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controlCard
            tabCard
            footer
        }
        .padding(20)
        .frame(width: 640)
        .alert("Bạn có chắc chắn muốn thiết lập lại cấu hình mặc định?", isPresented: $confirmDefaults) {
            Button("Có") { prefs.preferences = prefs.preferences.resetToDefaults() }
            Button("Không", role: .cancel) {}
        }
        .alert("Nhập cài đặt từ OpenKey?", isPresented: $confirmImport) {
            Button("Có") { model.onImportOpenKey() }
            Button("Không", role: .cancel) {}
        } message: {
            Text("Kiểu gõ, phím chuyển và các tuỳ chọn sẽ được lấy từ OpenKey trên máy này.")
        }
        .sheet(isPresented: $model.showExcludedApps) {
            ExcludedAppsView(prefs: prefs) { model.showExcludedApps = false }
        }
    }

    // MARK: Control card

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelHeader("Điều khiển")
            VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) {
                PanelRow("Kiểu gõ:") {
                    Picker("", selection: p.inputType) {
                        Text("Telex").tag(InputType.telex)
                        Text("VNI").tag(InputType.vni)
                        Text("Simple Telex 1").tag(InputType.simpleTelex1)
                        Text("Simple Telex 2").tag(InputType.simpleTelex2)
                    }
                    .labelsHidden()
                    .frame(width: PanelMetrics.controlWidth)
                }
                PanelRow("Phím chuyển:") {
                    HStack(spacing: 6) {
                        modifierToggle("⌃", .control)
                        modifierToggle("⌥", .option)
                        modifierToggle("⌘", .command)
                        modifierToggle("⇧", .shift)
                        HotkeyRecorder(hotkey: p.hotkey, onRecording: model.onRecordingHotkey)
                            .frame(width: 64, height: 22)
                            .padding(.leading, 4)
                        SwitchRow("Kêu beep", isOn: p.beepOnSwitch, fill: false)
                            .padding(.leading, 10)
                    }
                }
                if !prefs.preferences.hotkey.isUsable {
                    // Old or imported settings: fewer than two keys is not usable
                    Text("Phím chuyển cần ít nhất 2 phím, trong đó có một phím ⌃ ⌥ ⌘ ⇧")
                        .font(.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                PanelRow("Chế độ gõ:") {
                    Picker("", selection: p.vietnamese) {
                        Text("Tiếng Việt").tag(true)
                        Text("English").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: PanelMetrics.controlWidth)
                }
            }
            .panelCard()
        }
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

    // MARK: Tab card

    private var tabCard: some View {
        // ZStack so the old and new tab cross-fade in place instead of stacking during the transition
        ZStack(alignment: .topLeading) {
            tabContent
                .id(model.tab)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, minHeight: Self.tabHeight, maxHeight: Self.tabHeight, alignment: .topLeading)
        .padding(.top, 14)  // room for the lower half of the tab bar
        .panelCard()
        .animation(.easeInOut(duration: 0.2), value: model.tab)
        // The tab bar straddles the card's top border, NSTabView style.
        .overlay(alignment: .top) {
            TabBar(selection: $model.tab)
                .padding(.horizontal, 16)
                .alignmentGuide(.top) { $0[VerticalAlignment.center] }
        }
        .padding(.top, 10)  // room for the upper half of the tab bar
    }

    @ViewBuilder private var tabContent: some View {
        switch model.tab {
        case .typing: typingTab
        case .shortcuts: shortcutsTab
        case .system: systemTab
        case .info: InfoView()
        }
    }

    private var typingTab: some View {
        TwoColumns {
            SwitchRow("Đặt dấu oà, uý (thay vì òa, úy)", isOn: p.modernOrthography)
            SwitchRow("Sửa lỗi gợi ý (trình duyệt, Excel,...)", isOn: p.fixRecommendBrowser)
            SwitchRow("Viết Hoa chữ cái đầu câu", isOn: p.upperCaseFirstChar)
            SwitchRow("Chuyển chế độ thông minh", isOn: p.rememberPerApp)
            SwitchRow("Cho phép bỏ dấu tự do", isOn: p.freeMark)
            SwitchRow("Tắt tiếng Việt khi bộ gõ hệ thống khác tiếng Anh", isOn: p.disableOnNonEnglishInputSource)
        } right: {
            SwitchRow("Kiểm tra chính tả", isOn: p.checkSpelling)
            Group {
                SwitchRow("Tự khôi phục phím với từ sai", isOn: p.restoreIfWrong)
                SwitchRow("Cho phép \"z w j f\" làm phụ âm", isOn: p.allowConsonantZFWJ)
                SwitchRow("Tạm tắt chính tả bằng phím ⌃", isOn: p.tempOffSpellingWithControl)
            }
            .disabled(!prefs.preferences.checkSpelling)
            SwitchRow("Tạm tắt LiteKey bằng phím ⌘", isOn: p.tempOffEngineWithCommand)
        }
    }

    private var shortcutsTab: some View {
        TwoColumns {
            SwitchRow("Cho phép gõ tắt", isOn: p.useMacro)
            Group {
                SwitchRow("Gõ tắt cả khi tắt gõ tiếng Việt", isOn: p.useMacroInEnglishMode)
                SwitchRow("Tự động viết hoa theo phím tắt", isOn: p.autoCapsMacro)
            }
            .disabled(!prefs.preferences.useMacro)
            ActionRow("Bảng gõ tắt...") { model.onOpenMacros() }
        } right: {
            SwitchRow("Gõ nhanh (cc=ch, gg=gi, kk=kh, nn=ng, qq=qu, pp=ph, tt=th)", isOn: p.quickTelex)
            SwitchRow("Gõ tắt phụ âm đầu: f→ph, j→gi, w→qu", isOn: p.quickStartConsonant)
            SwitchRow("Gõ tắt phụ âm cuối: g→ng, h→nh, k→ch", isOn: p.quickEndConsonant)
        }
    }

    private var systemTab: some View {
        TwoColumns {
            SwitchRow("Hiện biểu tượng trên thanh Dock", isOn: p.showIconOnDock)
            SwitchRow("Bật bảng này khi khởi động", isOn: p.showPanelOnStartup)
            SwitchRow("Biểu tượng hiện đại trên thanh menu", isOn: p.modernMenuIcon)
            SwitchRow("Khởi động cùng macOS", isOn: Binding(
                get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            SwitchRow("Tương thích Telex trên các Layout khác (Dvorak, Colemak, ...)", isOn: p.layoutCompatibility)
        } right: {
            SwitchRow("Sửa lỗi trên Chromium", isOn: p.fixChromiumBrowser)
                .disabled(!prefs.preferences.fixRecommendBrowser)
            SwitchRow("Gửi từng phím (bật nếu bị lỗi)", isOn: p.sendKeyStepByStep)
            ActionRow("Ứng dụng loại trừ...") { model.showExcludedApps = true }
            ActionRow("Nhập cài đặt từ OpenKey...") { confirmImport = true }
                .disabled(!model.canImportOpenKey())
        }
    }

    // MARK: Footer: permission status and buttons

    /// Status pill on top, three equal-width buttons below.
    private var footer: some View {
        VStack(spacing: 12) {
            statusPill
            HStack(spacing: 10) {
                footerButton("Kết thúc") { model.onQuit() }
                    .glassButton()
                footerButton("Mặc định") { confirmDefaults = true }
                    .glassButton()
                footerButton("OK") { model.onClose() }
                    .keyboardShortcut(.defaultAction)
                    .glassButton(prominent: true)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }

    // The frame goes inside the label so the bezel grows; a frame outside Button does not widen it on macOS.
    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(width: 96) }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.hasPermission ? Color.green : Color.red)
                .frame(width: 7, height: 7)
            if model.hasPermission {
                Text("Ứng dụng đang hoạt động")
                    .foregroundColor(.secondary)
            } else {
                Text("Bạn chưa cấp quyền cho ứng dụng hoạt động!")
                    .foregroundColor(.red)
                Button("Thử lại") { model.onRetryPermission() }
                    .buttonStyle(.link)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .glassCapsule()
        .accessibilityElement(children: .contain)
    }
}
