import AppKit
import SwiftUI

/// Info tab: identity and features in the same two equal columns as the other tabs, notice centered below.
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
        VStack(spacing: 12) {
            TwoColumns {
                identity
            } right: {
                features
            }

            // Copyright and no-warranty notice required in the UI by GPL v3 section 5(d)
            Text("© 2026 Các tác giả LiteKey. "
                 + "Phần mềm tự do theo GNU GPL v3, không kèm bất kỳ bảo hành nào.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var identity: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("LiteKey").font(.system(size: 20, weight: .semibold))
            Text(version).font(.caption).foregroundColor(.secondary)
            HStack(spacing: 10) {
                Link("Mã nguồn", destination: Self.sourceURL)
                Link("GPL v3", destination: Self.licenseURL)
            }
            .font(.caption)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bộ gõ tiếng Việt cho macOS").font(.headline)
            feature("Telex, VNI, Simple Telex, gõ tắt, nhớ chế độ theo ứng dụng", icon: "keyboard")
            feature("Gọn nhẹ, phản hồi tức thì, không cần thêm bộ gõ hệ thống", icon: "bolt")
            feature("Không thu thập dữ liệu, không kết nối mạng", icon: "lock.shield")
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Icon in a fixed-width column so every line of text starts at the same x
    private func feature(_ text: LocalizedStringKey, icon: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(text)
        }
    }
}
