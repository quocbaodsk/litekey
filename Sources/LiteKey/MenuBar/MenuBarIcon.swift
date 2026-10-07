import AppKit

/// The V/E menu bar icon.
/// - Modern (default): a monochrome template image the system tints for light/dark appearance.
///   Vietnamese: filled box with a knocked-out letter; English: outlined box with a solid letter.
/// - Classic: a bold V/E letter.
enum MenuBarIcon {
    static func image(vietnamese: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let box = rect.insetBy(dx: 1, dy: 1)
            let path = NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5)
            let letter = vietnamese ? "V" : "E"
            let font = NSFont.systemFont(ofSize: 11, weight: .bold)
            if vietnamese {
                NSColor.black.setFill()
                path.fill()
                // Knock out the letter by drawing it in erase mode
                NSGraphicsContext.current?.compositingOperation = .destinationOut
            } else {
                NSColor.black.setStroke()
                path.lineWidth = 1.2
                path.stroke()
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let text = NSAttributedString(string: letter, attributes: attributes)
            let textSize = text.size()
            text.draw(at: NSPoint(x: box.midX - textSize.width / 2, y: box.midY - textSize.height / 2))
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        return image
    }
}
