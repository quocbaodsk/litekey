import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import LiteKeyCore

/// Owns the CGEventTap. Decisions are made by `handler`; this class only creates, re-enables and
/// removes the tap.
///
/// The tap lives on the main run loop and only sees key events. Clicks come from a global NSEvent
/// monitor, which can't block anything, so the mouse keeps working even if the tap goes bad.
/// On permission loss the tap is disabled at once and never re-enabled.
public final class EventTap {
    public typealias Handler = (CGEventTapProxy, CGEventType, CGEvent) -> Unmanaged<CGEvent>?

    /// Keyboard events only
    static let eventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]

    /// Written only on main while holding `lock`; `disable()` reads it from background threads under `lock`
    private var tap: CFMachPort?
    private let lock = NSLock()
    private var runLoopSource: CFRunLoopSource?
    private var mouseMonitor: Any?
    private let handler: Handler
    private let onMouseDown: () -> Void
    private var disableGuard = TapDisableGuard()

    /// The tap was re-enabled after macOS disabled it
    public var onReenabled: ((CGEventType) -> Void)?
    /// The tap was disabled and Accessibility permission is gone; the tap has been removed
    public var onPermissionLost: (() -> Void)?
    /// macOS kept disabling the tap while permission still reads as granted; the tap was removed so the
    /// keyboard does not hang
    public var onGaveUp: (() -> Void)?

    public var isRunning: Bool { tap != nil }

    /// The tap exists and macOS has it enabled (used by the watchdog to detect a silently disabled tap)
    public var isEnabled: Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// Re-enables the tap if macOS disabled it. Returns `true` if it had to be re-enabled.
    @discardableResult
    public func reenableIfNeeded() -> Bool {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// - Parameters:
    ///   - handler: handles one key event (on main)
    ///   - onMouseDown: a mouse click happened in another app (on main)
    public init(handler: @escaping Handler, onMouseDown: @escaping () -> Void) {
        self.handler = handler
        self.onMouseDown = onMouseDown
    }

    /// Creates the tap. Call on main.
    @discardableResult
    public func start() -> Bool {
        if tap != nil { return true }

        let mask = Self.eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
            return me.dispatch(proxy: proxy, type: type, event: event)
        }

        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                             place: .headInsertEventTap,
                                             options: .defaultTap,
                                             eventsOfInterest: mask,
                                             callback: callback,
                                             userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        lock.lock()
        tap = newTap
        lock.unlock()
        runLoopSource = source
        disableGuard.reset()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.onMouseDown()
        }
        return true
    }

    /// Disables the tap immediately (a disabled tap blocks nothing). Safe from any thread; used when a
    /// background thread detects permission loss, before main removes the tap with `stop()`.
    public func disable() {
        lock.lock(); defer { lock.unlock() }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    /// Removes the tap. Call on main.
    public func stop() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        lock.lock()
        tap = nil
        lock.unlock()
        runLoopSource = nil
    }

    private func dispatch(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables the tap when the callback is slow or on certain user input; re-enable it at once.
        // If permission is gone, or the tap keeps getting disabled (permission may be misreported), fail
        // open here: re-enabling a tap without permission can block the keyboard until the process exits.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            guard let current = tap else { return Unmanaged.passUnretained(event) }
            let trusted = AXIsProcessTrusted()
            switch disableGuard.tapDisabled(at: DispatchTime.now().uptimeNanoseconds, trusted: trusted) {
            case .reenable:
                CGEvent.tapEnable(tap: current, enable: true)
                onReenabled?(type)
            case .stop:
                CGEvent.tapEnable(tap: current, enable: false)
                // Remove it fully once the callback has returned
                DispatchQueue.main.async { [weak self] in
                    self?.stop()
                    if trusted { self?.onGaveUp?() } else { self?.onPermissionLost?() }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        return handler(proxy, type, event)
    }
}
