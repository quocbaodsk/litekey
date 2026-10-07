import SwiftUI

/// Control Panel building blocks, System Settings style: rounded cards, label on the left and control on
/// the right, the same row height and spacing everywhere. Cards are content, so they get no glass.
enum PanelMetrics {
    static let cornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let rowHeight: CGFloat = 24
    static let rowSpacing: CGFloat = 10
    static let columnSpacing: CGFloat = 20
    /// Right-hand controls in the control card share this width so their edges line up
    static let controlWidth: CGFloat = 180
}

extension View {
    /// Content card: faint fill and a hairline border, like a grouped Form section
    func panelCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
        return self
            .padding(PanelMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { shape.fill(Color.primary.opacity(0.04)) }
            .overlay { shape.strokeBorder(Color.primary.opacity(0.08)) }
    }
}

/// Section title above a card, aligned with the labels inside it
struct PanelHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.leading, PanelMetrics.cardPadding)
    }
}

/// Label on the left, any control on the right
struct PanelRow<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            content
        }
        .frame(minHeight: PanelMetrics.rowHeight)
    }
}

/// On/off option: label on the left (wraps when long), small switch on the right
struct SwitchRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    /// false: label and switch sit together at their natural width (inline use)
    var fill = true
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>, fill: Bool = true) {
        self.title = title
        _isOn = isOn
        self.fill = fill
    }

    var body: some View {
        HStack(spacing: fill ? 12 : 8) {
            BalancedWrap {
                Text(title)
                    .foregroundColor(isEnabled ? .primary : .secondary)
            }
            .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
            // Inline: never squeezed (macOS 15 shrank "Kêu beep" to nothing next to the hotkey field)
            .fixedSize(horizontal: !fill, vertical: false)
            // Clicking the label flips the switch, as it did with the old checkboxes
            .contentShape(Rectangle())
            .onTapGesture { if isEnabled { isOn.toggle() } }
            // The switch below carries the same label for VoiceOver
            .accessibilityHidden(true)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
        .frame(minHeight: PanelMetrics.rowHeight)
    }
}

/// Row that opens a window, sheet or dialog: title on the left, chevron on the right, the whole row clickable
struct ActionRow: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(minHeight: PanelMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        // Hover highlight reaches a little past the row so the text stays aligned with the other rows
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(hovered && isEnabled ? 0.06 : 0))
        }
        .padding(.horizontal, -6)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { hovered = inside }
        }
    }
}

/// Two equal columns split by a full-height divider
struct TwoColumns<Left: View, Right: View>: View {
    let left: Left
    let right: Right

    init(@ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.left = left()
        self.right = right()
    }

    var body: some View {
        HStack(alignment: .top, spacing: PanelMetrics.columnSpacing) {
            column(left)
            Divider()
            column(right)
        }
    }

    private func column<Content: View>(_ content: Content) -> some View {
        VStack(alignment: .leading, spacing: PanelMetrics.rowSpacing) { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Modifier key (⌃ ⌥ ⌘ ⇧) as a toggle button: tinted glass when on, plain glass when off
struct KeycapToggle: View {
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        // Flexible label + fixed outer frame: on and off keys get the same width even though the tinted
        // and plain glass styles use different padding.
        Button { isOn.toggle() } label: {
            Text(symbol).frame(maxWidth: .infinity)
        }
        .glassButton(prominent: isOn)
        .frame(width: 34)
        .accessibilityLabel(Text(symbol))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Wraps a long label into lines of similar length ("Gõ tắt phụ âm đầu: f→ph,\nj→gi, w→qu" instead of
/// leaving "w→qu" alone on the second line). Keeps the line count; only narrows the text.
struct BalancedWrap: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let size = text.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width.map { min($0, size.width) } ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let text = subviews.first else { return }
        let width = balancedWidth(text, maxWidth: bounds.width)
        text.place(at: bounds.origin, proposal: ProposedViewSize(width: width, height: bounds.height))
    }

    /// Narrowest width that still needs no more lines than `maxWidth` does
    private func balancedWidth(_ text: LayoutSubview, maxWidth: CGFloat) -> CGFloat {
        let height = { (width: CGFloat) in text.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let target = height(maxWidth)
        // One line: nothing to balance
        guard target > height(.infinity) + 1 else { return maxWidth }
        var low = maxWidth / 2
        var high = maxWidth
        for _ in 0..<8 {
            let mid = (low + high) / 2
            if height(mid) <= target { high = mid } else { low = mid }
        }
        return high.rounded(.up)
    }
}
