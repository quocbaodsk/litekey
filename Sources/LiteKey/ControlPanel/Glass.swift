import SwiftUI

/// Liquid Glass on macOS 26+, plain styles before that. Only controls and navigation get glass (buttons,
/// keycaps, status pill, sidebar), not content. Also gated on the compiler: Xcode 16 doesn't have
/// the glass APIs.
enum LiquidGlass {
    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }
}

extension View {
    /// Glass button; `prominent` for the primary button (OK, dialog default)
    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            // Explicit shape: with .automatic, .glassProminent draws a rounded rectangle while .glass
            // draws a capsule, so buttons side by side don't match.
            Group {
                if prominent {
                    self.buttonStyle(.glassProminent)
                } else {
                    self.buttonStyle(.glass)
                }
            }
            .buttonBorderShape(.roundedRectangle)
        } else {
            legacyButton(prominent: prominent)
        }
        #else
        legacyButton(prominent: prominent)
        #endif
    }

    /// Capsule background: glass on macOS 26+, a faint fill on older versions
    @ViewBuilder func glassCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        #else
        self.background(Capsule().fill(Color.primary.opacity(0.06)))
        #endif
    }

    /// Glass in any shape (navigation chrome); older versions get a faint fill and a hairline border
    @ViewBuilder func glassPanel<S: InsettableShape>(in shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            legacyPanel(in: shape)
        }
        #else
        legacyPanel(in: shape)
        #endif
    }

    private func legacyPanel<S: InsettableShape>(in shape: S) -> some View {
        self
            .background { shape.fill(Color.primary.opacity(0.05)) }
            .overlay { shape.strokeBorder(Color.primary.opacity(0.08)) }
    }

    @ViewBuilder private func legacyButton(prominent: Bool) -> some View {
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self
        }
    }
}
