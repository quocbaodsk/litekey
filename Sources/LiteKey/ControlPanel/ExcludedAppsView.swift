import AppKit
import LiteKeyCore
import SwiftUI
import UniformTypeIdentifiers

/// Apps that always type in English
struct ExcludedAppsView: View {
    @ObservedObject var prefs: PreferencesModel
    var onDone: () -> Void
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ứng dụng luôn gõ tiếng Anh").font(.headline)
            List(selection: $selected) {
                ForEach(prefs.preferences.excludedApps, id: \.self) { bundle in
                    HStack(spacing: 8) {
                        Image(nsImage: Self.appIcon(bundle))
                            .resizable()
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                        Text(Self.appName(bundle))
                    }
                    .tag(bundle)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 160)
            HStack {
                Button("Thêm...") { addApps() }
                    .glassButton()
                Button("Xoá") {
                    if let selected { prefs.preferences.excludedApps.removeAll { $0 == selected } }
                    selected = nil
                }
                .disabled(selected == nil)
                .glassButton()
                Spacer()
                Button("Đóng") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .glassButton(prominent: true)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    static func appName(_ bundle: String) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.localizedName {
            return running
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// The app's own icon; a generic app icon when it is no longer installed
    static func appIcon(_ bundle: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            return NSWorkspace.shared.icon(for: .application)
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !prefs.preferences.excludedApps.contains(id) {
                prefs.preferences.excludedApps.append(id)
            }
        }
    }
}
