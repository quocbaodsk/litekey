import AppKit
import SwiftUI

/// "Thông tin" page: identity card, features card, notice below.
struct InfoView: View {
    private static let sourceURL = URL(string: "https://github.com/quocbaodsk/litekey")!
    private static let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
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
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("LiteKey").font(.system(size: 20, weight: .semibold))
                Text(version).font(.callout).foregroundColor(.secondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 14) {
                Link("Mã nguồn", destination: Self.sourceURL)
                Link("GPL v3", destination: Self.licenseURL)
            }
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader("Bộ gõ tiếng Việt cho macOS")
            feature("Telex, VNI, Simple Telex, gõ tắt, nhớ chế độ theo ứng dụng", icon: "keyboard")
            feature("Gọn nhẹ, phản hồi tức thì, không cần thêm bộ gõ hệ thống", icon: "bolt")
            feature("Không thu thập dữ liệu, không kết nối mạng", icon: "lock.shield")
        }
    }

    private func feature(_ text: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 10) {
            RowIcon(symbol: icon)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
