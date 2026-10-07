import AppKit

// Menu bar only app with no Dock icon (LSUIElement in Info.plist).
let app = NSApplication.shared
#if DEBUG
// UI snapshot run for CI (see UISnapshot.swift)
if let dir = ProcessInfo.processInfo.environment["LITEKEY_SNAPSHOT_DIR"] {
    let snapshot = UISnapshot(dir: dir)
    app.delegate = snapshot
    app.run()
    exit(0)
}
#endif
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // AppDelegate switches to .regular when the Dock icon option is on
app.run()
