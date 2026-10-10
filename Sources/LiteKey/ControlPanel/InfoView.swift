import AppKit
import SwiftUI

/// "Thông tin" page, centered like an About window: identity card, three feature tiles, notice below.
struct InfoView: View {
    private static let websiteURL = URL(string: "https://litekey.quocbao.dev")!
    private static let sourceURL = URL(string: "https://github.com/quocbaodsk/litekey")!
    private static let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = Bundle.main.shortVersion ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        // Skip the build number when it equals the version (build.sh sets both to VERSION).
        return short == build ? "Phiên bản \(short)" : "Phiên bản \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: PanelMetrics.cardSpacing) {
            identity.panelCard()
            features.panelCard()
            // Copyright and no-warranty notice required in the UI by GPL v3 section 5(d)
            Text("© 2026 LiteKey.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    private var identity: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("LiteKey").font(.system(size: 22, weight: .semibold))
            Text("Bộ gõ tiếng Việt cho macOS").foregroundColor(.secondary)
            Text(version)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
            // Each link opens in the browser; the app itself never goes online
            HStack(spacing: 20) {
                link("Trang chủ", icon: "globe", to: Self.websiteURL)
                link("Mã nguồn", icon: "chevron.left.forwardslash.chevron.right", to: Self.sourceURL)
                link("GPL v3", icon: "doc.text", to: Self.licenseURL)
            }
            .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func link(_ title: LocalizedStringKey, icon: String, to url: URL) -> some View {
        Link(destination: url) {
            Label(title, systemImage: icon)
        }
        .help(url.absoluteString)
    }

    /// Equal tiles split by hairlines, the same divider as the option columns on the other pages
    private var features: some View {
        HStack(alignment: .top, spacing: PanelMetrics.columnSpacing) {
            feature("Telex, VNI, Simple Telex, gõ tắt, nhớ chế độ theo ứng dụng", icon: "keyboard")
            Divider()
            feature("Gọn nhẹ, phản hồi tức thì, không cần thêm bộ gõ hệ thống", icon: "bolt")
            Divider()
            feature("Không thu thập dữ liệu, không kết nối mạng", icon: "lock.shield")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func feature(_ text: LocalizedStringKey, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(height: 24)
                .accessibilityHidden(true)
            BalancedWrap {
                Text(text).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
