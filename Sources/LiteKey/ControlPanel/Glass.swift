import SwiftUI

/// Liquid Glass on macOS 26+, plain styles before that. Only controls get glass (buttons, tab bar,
/// status pill), not content. Also gated on the compiler: Xcode 16 doesn't have the glass APIs.
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

    @ViewBuilder private func legacyButton(prominent: Bool) -> some View {
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self
        }
    }
}
