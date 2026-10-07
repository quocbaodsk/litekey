import SwiftUI

/// Control Panel tab bar: Liquid Glass on macOS 26+, segmented picker on older versions.
struct TabBar: View {
    @Binding var selection: ControlPanelModel.Tab

    var body: some View {
        // Xcode 16 (Swift 6.1) lacks the glass APIs, so also gate on the compiler version.
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassTabBar(selection: $selection)
        } else {
            SegmentedTabBar(selection: $selection)
        }
        #else
        SegmentedTabBar(selection: $selection)
        #endif
    }
}

private struct SegmentedTabBar: View {
    @Binding var selection: ControlPanelModel.Tab

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(ControlPanelModel.Tab.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private struct GlassTabBar: View {
    @Binding var selection: ControlPanelModel.Tab
    @Namespace private var indicator
    @State private var hovered: ControlPanelModel.Tab?
    @State private var frames: [ControlPanelModel.Tab: CGRect] = [:]
    @GestureState private var isPressing = false

    private let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
    private let space = "TabBar"

    var body: some View {
        // The container lets the glass pill morph from the old tab to the new one via glassEffectID.
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(ControlPanelModel.Tab.allCases, id: \.self) { tab in
                    segment(tab)
                }
            }
        }
        .padding(3)
        // Solid (non-glass) background hides the content box border beneath the bar and keeps the
        // selected tab's glass from nesting glass inside glass.
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quinary) }
        }
        .coordinateSpace(.named(space))
        // One gesture for the whole bar instead of a Button per tab: press selects, and dragging
        // sideways moves the glass pill to the tab nearest the pointer (iTerm2 style).
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                .updating($isPressing) { _, pressing, _ in pressing = true }
                .onChanged { select(nearestTab(to: $0.location.x)) }
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressing)
    }

    private func segment(_ tab: ControlPanelModel.Tab) -> some View {
        let isSelected = selection == tab
        return Text(tab.title)
            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            // Each segment expands fully so the HStack splits the width evenly.
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background { if hovered == tab && !isSelected { shape.fill(.primary.opacity(0.06)) } }
            // Glass must be applied to the text view itself: the container renders glass in a layer
            // above, so glass in .background would cover the text.
            .glassEffect(isSelected ? .regular.interactive() : .identity, in: shape)
            .glassEffectID(tab, in: indicator)
            // The glass pill lifts slightly while the mouse is held.
            .scaleEffect(isSelected && isPressing ? 1.06 : 1)
            .contentShape(shape)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(space)) } action: { frames[tab] = $0 }
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.15)) {
                    if inside { hovered = tab } else if hovered == tab { hovered = nil }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { select(tab) }
    }

    private func select(_ tab: ControlPanelModel.Tab?) {
        guard let tab, tab != selection else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = tab }
    }

    /// Tab whose center is nearest x; dragging past either end sticks to the first/last tab.
    private func nearestTab(to x: CGFloat) -> ControlPanelModel.Tab? {
        frames.min { abs($0.value.midX - x) < abs($1.value.midX - x) }?.key
    }
}
#endif
