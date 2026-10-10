import AppKit
import SwiftUI

/// Control Panel sidebar: app identity on top, then one row per page. No ⌘1...⌘4 shortcuts: they would
/// reach the window before the hotkey recorder, so a ⌘+digit hotkey could not be recorded.
/// macOS 26+: a floating glass panel inset from the window edges, the traffic lights sitting on it.
/// Older versions: the classic full-height sidebar material with a divider.
struct Sidebar: View {
    @Binding var selection: ControlPanelModel.Tab
    @Namespace private var pill

    static let width: CGFloat = 184
    /// Gap between the floating glass panel and the window edges
    static let inset: CGFloat = 8

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    var body: some View {
        if LiquidGlass.isAvailable {
            content
                // Roughly concentric with the toolbar window's corner, minus the inset
                .glassPanel(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(Self.inset)
                .padding(.trailing, -Self.inset / 2)  // the page has its own leading padding
        } else {
            content
                .background(SidebarBackground())
                // Divider() would be horizontal outside a stack
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            identity
                .padding(.top, 44)  // below the traffic lights (bottom edge at y 33)
                .padding(.bottom, 16)
            VStack(spacing: 2) {
                ForEach(ControlPanelModel.Tab.allCases, id: \.self) { tab in
                    SidebarItem(tab: tab, isSelected: selection == tab, pill: pill) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = tab }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
    }

    private var identity: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            Text("LiteKey \(version)")
                .font(.system(size: 13, weight: .semibold))
            Text("Bộ gõ Tiếng Việt cho macOS")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct SidebarItem: View {
    let tab: ControlPanelModel.Tab
    let isSelected: Bool
    let pill: Namespace.ID
    let action: () -> Void
    @State private var hovered = false

    private let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(tab.title)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background {
                // One selection pill that slides between rows as the page changes
                if isSelected {
                    shape.fill(Color.accentColor.opacity(0.16))
                        .matchedGeometryEffect(id: "pill", in: pill)
                } else if hovered {
                    shape.fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovered = inside }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Native sidebar material for macOS 13–15, behind the traffic lights too
private struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
