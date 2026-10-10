import AppKit
import SwiftUI

/// Control Panel building blocks, System Settings style: rounded cards, the same row height and spacing
/// everywhere. Cards are content, so they get no glass. Colors come from the system (accent, labels).
enum PanelMetrics {
    static let cornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let rowHeight: CGFloat = 24
    static let rowSpacing: CGFloat = 6
    static let columnSpacing: CGFloat = 16
    /// Between cards on a page
    static let cardSpacing: CGFloat = 12
    /// Labels in the control card share this width so the controls start on one line and run to the
    /// card's right edge, like the option columns below
    static let labelWidth: CGFloat = 96
    static let iconSize: CGFloat = 20
}

enum PanelColors {
    /// White cards on the light window background; a faint lift in dark mode
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.05) : NSColor.white.withAlphaComponent(0.85)
    })
}

extension View {
    /// Content card: light fill, hairline border and a soft shadow, like a grouped Form section
    func panelCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)
        return self
            .padding(PanelMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(PanelColors.card)
                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
            }
            .overlay { shape.strokeBorder(Color.primary.opacity(0.08)) }
    }

    /// A page that fits the window doesn't rubber-band; only one that really scrolls does
    @ViewBuilder func bouncesOnlyWhenScrollable() -> some View {
        if #available(macOS 13.3, *) {
            self.scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}

/// Section title inside a card, above its rows
struct PanelHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

/// Fixed-width label on the left, the control after it filling the rest of the row up to the card's right edge
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
                .frame(width: PanelMetrics.labelWidth, alignment: .leading)
            // A frame, not a trailing Spacer: the stack's spacing before a Spacer cut 12 pt off the right edge
            HStack(spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: PanelMetrics.rowHeight + 4)
    }
}

/// SF Symbol in a small rounded tile at the start of a row
struct RowIcon: View {
    let symbol: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: PanelMetrics.iconSize, height: PanelMetrics.iconSize)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06))
            }
            .opacity(isEnabled ? 1 : 0.5)
            .accessibilityHidden(true)
    }
}

/// "?" next to an option: hover shows the explanation as a tooltip, click shows it in a popover
struct HelpButton: View {
    let text: LocalizedStringKey
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(Text(text))
        .accessibilityLabel(Text("Trợ giúp"))
        .accessibilityHint(Text(text))
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)
                .padding(12)
        }
    }
}

/// On/off option: optional icon, label (wraps when long), optional help, small switch on the right
struct SwitchRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    /// false: label and switch sit together at their natural width (inline use)
    var fill = true
    var icon: String?
    var help: LocalizedStringKey?
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, isOn: Binding<Bool>, fill: Bool = true, icon: String? = nil,
         help: LocalizedStringKey? = nil) {
        self.title = title
        _isOn = isOn
        self.fill = fill
        self.icon = icon
        self.help = help
    }

    var body: some View {
        HStack(spacing: fill ? 10 : 8) {
            if let icon { RowIcon(symbol: icon) }
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
            if let help { HelpButton(text: help) }
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
    var icon: String?
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    init(_ title: LocalizedStringKey, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { RowIcon(symbol: icon) }
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

/// Two equal columns of `GridRow`s split by a full-height hairline. Rows line up across the columns: a
/// two-line label on one side keeps its neighbour on the other side centered beside it.
struct OptionGrid<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: PanelMetrics.columnSpacing * 2 + 1,
             verticalSpacing: PanelMetrics.rowSpacing) {
            content
        }
        .overlay {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
        }
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
/// leaving "w→qu" alone on the second line). Keeps the line count; only narrows the text. Reports the
/// narrowed width, so a centered parent centers the balanced lines.
struct BalancedWrap: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        guard let maxWidth = proposal.width, maxWidth.isFinite else {
            return text.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        }
        let width = balancedWidth(text, maxWidth: maxWidth)
        let size = text.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: min(width, size.width), height: size.height)
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
