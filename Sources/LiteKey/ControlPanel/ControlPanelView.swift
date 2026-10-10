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

        var subtitle: String {
            switch self {
            case .typing: return "Thiết lập kiểu gõ và các tuỳ chọn cơ bản"
            case .shortcuts: return "Gõ tắt và gõ nhanh phụ âm"
            case .system: return "Khởi động, giao diện và tương thích ứng dụng"
            case .info: return "Phiên bản, giấy phép và mã nguồn"
            }
        }

        var symbol: String {
            switch self {
            case .typing: return "keyboard"
            case .shortcuts: return "doc.text"
            case .system: return "gearshape"
            case .info: return "info.circle"
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

extension NSWindow {
    /// Control Panel window: the sidebar runs under the transparent title bar, System Settings style.
    /// The title stays set (hidden) for Mission Control and the Window menu.
    static func controlPanel(model: ControlPanelModel, title: String) -> NSWindow {
        let host = NSHostingController(rootView: ControlPanelView(model: model))
        // Fixed size: the hosting controller would add the title bar inset on top of the view's own height
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.setContentSize(ControlPanelView.size)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // Empty unified toolbar: moves the traffic lights to (19, 19), well inside the inset glass sidebar
        // instead of on its rounded corner (they sit at (9, 9) with a plain title bar)
        window.toolbar = NSToolbar(identifier: "ControlPanel")
        window.toolbarStyle = .unified
        return window
    }
}

/// Control Panel: sidebar on the left; on the right the page title and status, the page, and the
/// Defaults / Quit / OK buttons. The window keeps one size on every page; long pages scroll.
struct ControlPanelView: View {
    @ObservedObject var model: ControlPanelModel
    @ObservedObject var prefs: PreferencesModel
    @State private var confirmDefaults = false
    @State private var confirmImport = false

    static let size = CGSize(width: 880, height: 560)
    /// Leading/trailing padding of the header, page and footer
    private static let margin: CGFloat = 20
    /// All three footer buttons share one width
    private static let buttonWidth: CGFloat = 96

    init(model: ControlPanelModel) {
        _model = ObservedObject(wrappedValue: model)
        _prefs = ObservedObject(wrappedValue: model.preferences)
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $model.tab)
            VStack(alignment: .leading, spacing: 0) {
                header
                page
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // Explicit, so the 2x snapshots (drawn from the view, without the window) get it too
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
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

    // MARK: Header: page title, permission status

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.tab.title)
                        .font(.system(size: 20, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(model.tab.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 12)
                if model.hasPermission { statusPill }
            }
            if !model.hasPermission { permissionBanner }
        }
        .padding(.horizontal, Self.margin)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
            Text("Ứng dụng đang hoạt động")
                .foregroundColor(.secondary)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassCapsule()
        .accessibilityElement(children: .combine)
    }

    /// Missing permission: nothing works until it is granted, so it gets a full-width banner on every page
    private var permissionBanner: some View {
        // Plain tinted fill, not glass: the glass "Thử lại" button would otherwise sit glass on glass
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .accessibilityHidden(true)
            Text("Bạn chưa cấp quyền cho ứng dụng hoạt động!")
                .foregroundColor(.red)
            Spacer(minLength: 12)
            Button("Thử lại") { model.onRetryPermission() }
                .controlSize(.small)
                .glassButton()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background { shape.fill(Color.red.opacity(0.08)) }
        .overlay { shape.strokeBorder(Color.red.opacity(0.25)) }
        .accessibilityElement(children: .contain)
    }

    // MARK: Page

    private var page: some View {
        // ZStack so the old and new page cross-fade in place instead of stacking during the transition.
        // One ScrollView per page, so a new page never opens scrolled.
        ZStack(alignment: .topLeading) {
            ScrollView {
                pageContent
                    .padding(.horizontal, Self.margin)
                    .padding(.bottom, 6)
            }
            .id(model.tab)
            .transition(.opacity)
        }
        .frame(maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: model.tab)
    }

    @ViewBuilder private var pageContent: some View {
        switch model.tab {
        case .typing: TypingPage(model: model, prefs: prefs)
        case .shortcuts: ShortcutsPage(model: model, prefs: prefs)
        case .system: SystemPage(model: model, prefs: prefs) { confirmImport = true }
        case .info: InfoView()
        }
    }

    // MARK: Footer

    /// Defaults on the left (resets settings), Quit and OK on the right
    private var footer: some View {
        HStack(spacing: 10) {
            Button { confirmDefaults = true } label: {
                Label("Mặc định", systemImage: "arrow.counterclockwise")
                    .frame(width: Self.buttonWidth)
            }
            .glassButton()
            Spacer(minLength: 12)
            footerButton("Kết thúc") { model.onQuit() }
                .glassButton()
            footerButton("OK") { model.onClose() }
                .keyboardShortcut(.defaultAction)
                .glassButton(prominent: true)
        }
        .controlSize(.large)
        .padding(.horizontal, Self.margin)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    // The frame goes inside the label so the bezel grows; a frame outside Button does not widen it on macOS.
    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(width: Self.buttonWidth) }
    }
}
