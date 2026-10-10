import SwiftUI

/// One-of-a-few choice (Kiểu gõ, Chế độ gõ). macOS 26+: a glass pill that slides between the segments; press
/// and drag sideways to move it, like the old tab bar. Older versions: the native segmented picker.
struct SegmentedChoice<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    init(_ title: LocalizedStringKey, selection: Binding<Value>, options: [(value: Value, label: String)]) {
        self.title = title
        _selection = selection
        self.options = options
    }

    var body: some View {
        // Xcode 16 (Swift 6.1) lacks the glass APIs, so also gate on the compiler version
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassSegments(title: title, selection: $selection, options: options)
        } else {
            nativePicker
        }
        #else
        nativePicker
        #endif
    }

    private var nativePicker: some View {
        Picker(title, selection: $selection) {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index].label).tag(options[index].value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private struct GlassSegments<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    @Namespace private var pill
    @State private var hovered: Int?
    /// Segment centers, for picking the segment nearest the pointer while dragging
    @State private var centers: [Int: CGFloat] = [:]
    @GestureState private var isPressing = false
    @Environment(\.isEnabled) private var isEnabled

    private let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
    private let space = "SegmentedChoice"

    var body: some View {
        // The container lets the pill morph from the old segment to the new one via glassEffectID
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(options.indices, id: \.self) { segment($0) }
            }
        }
        .padding(3)
        // Plain fill, not glass: the selected segment's glass must not sit on glass
        .background { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quinary) }
        .coordinateSpace(.named(space))
        // One gesture for the whole control instead of a button per segment: press selects, dragging
        // sideways moves the pill to the segment nearest the pointer
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                .updating($isPressing) { _, pressing, _ in pressing = true }
                .onChanged { select(nearest(to: $0.location.x)) }
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressing)
        // Keyboard, as with the native picker: focusable only with Full Keyboard Access on, so the window
        // doesn't open with a focus ring here; ←/→ move one segment
        .focusable(interactions: .activate)
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: _ = step(1)
            case .decrement: _ = step(-1)
            @unknown default: break
            }
        }
    }

    private func segment(_ index: Int) -> some View {
        let isSelected = options[index].value == selection
        return Text(options[index].label)
            .font(.system(size: 13, weight: isSelected ? .medium : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .lineLimit(1)
            // Every segment expands fully so the stack splits the width evenly
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background { if hovered == index && !isSelected { shape.fill(.primary.opacity(0.06)) } }
            // Glass goes on the text view itself: the container draws glass in a layer above, so glass in
            // .background would cover the text
            .glassEffect(isSelected ? .regular.interactive() : .identity, in: shape)
            .glassEffectID(index, in: pill)
            // The pill lifts slightly while the mouse is held
            .scaleEffect(isSelected && isPressing ? 1.04 : 1)
            .contentShape(shape)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(space)).midX } action: { centers[index] = $0 }
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.15)) {
                    if inside { hovered = index } else if hovered == index { hovered = nil }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { select(index) }
    }

    private func select(_ index: Int?) {
        guard isEnabled, let index, options.indices.contains(index), options[index].value != selection else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = options[index].value }
    }

    /// Moves the selection one segment left (-1) or right (+1), stopping at either end
    private func step(_ offset: Int) -> KeyPress.Result {
        guard let current = options.firstIndex(where: { $0.value == selection }) else { return .ignored }
        select(min(max(current + offset, 0), options.count - 1))
        return .handled
    }

    /// Dragging past either end sticks to the first or last segment
    private func nearest(to x: CGFloat) -> Int? {
        centers.min { abs($0.value - x) < abs($1.value - x) }?.key
    }
}
#endif
