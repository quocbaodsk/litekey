import AppKit
import LiteKeyPlatform
import SwiftUI

/// State shown on the permission screen, refreshed every second while the window is open.
final class PermissionModel: ObservableObject {
    /// macOS reports the app as trusted (`AXIsProcessTrusted`), though the tap may not be running yet
    @Published var trusted = PermissionMonitor.isTrusted
    /// Running from a temporary location (App Translocation, /tmp), where macOS never grants permission
    let badLocation: Bool = {
        let path = Bundle.main.bundlePath
        return path.contains("/AppTranslocation/") || path.hasPrefix("/private/tmp/") || path.hasPrefix("/tmp/")
    }()
    private var timer: Timer?

    func startUpdating() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            let trusted = PermissionMonitor.isTrusted
            if self?.trusted != trusted { self?.trusted = trusted }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopUpdating() {
        timer?.invalidate()
        timer = nil
    }
}

/// Accessibility permission screen. Closes itself once permission is granted.
struct PermissionView: View {
    @ObservedObject var model: PermissionModel
    var onOpenSettings: () -> Void
    var onReset: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Bạn chưa cấp quyền cho ứng dụng hoạt động!")
                .font(.headline)
            Text("LiteKey cần quyền Trợ năng (Accessibility) để nhận và gửi phím. Vào Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Trợ năng, bật LiteKey. LiteKey sẽ tự chạy khi đã có quyền.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if model.badLocation {
                Text("LiteKey đang chạy từ thư mục tạm nên macOS không cấp quyền được. Hãy chép LiteKey vào thư mục Ứng dụng (Applications) rồi mở lại từ đó.")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.trusted {
                Text("macOS đã cấp quyền, đang bật bộ gõ…")
                    .foregroundColor(.secondary)
            } else {
                Text("Công tắc LiteKey đã bật mà vẫn thấy cửa sổ này? Công tắc đó thuộc bản LiteKey cũ. Bấm \"Đặt lại quyền\" rồi bật lại LiteKey.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Mở Cài đặt hệ thống") { onOpenSettings() }
                    .keyboardShortcut(.defaultAction)
                    .glassButton(prominent: true)
                Button("Đặt lại quyền") { onReset() }
                    .glassButton()
                Button("Thử lại") { onRetry() }
                    .glassButton()
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { model.startUpdating() }
        .onDisappear { model.stopUpdating() }
    }
}
