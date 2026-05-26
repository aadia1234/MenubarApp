 import AppKit

/// A solid-black borderless window that sits one level above the menu bar,
/// visually hiding it without touching any system setting.
///
/// Hover-to-reveal: when the cursor enters the menu-bar zone the overlay
/// steps aside so the user can see and interact with the real menu bar
/// (including the app's own status item), then re-covers it on mouse-out.
final class MenuBarOverlay {

    static let shared = MenuBarOverlay()

    /// True while the overlay should be drawn (mode is active for this space).
    private(set) var isActive = false

    private var overlayWindow: NSWindow?
    private var mouseMonitor: Any?
    /// True while the cursor is in the menu-bar zone and the overlay is hidden.
    private var revealedByHover = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Public
    // Must be called on the main thread.

    func activate() {
        isActive = true
        makeWindowIfNeeded()
        updateVisibility()
        startHoverTracking()
    }

    func deactivate() {
        isActive = false
        revealedByHover = false
        updateVisibility()
        stopHoverTracking()
    }

    // MARK: - Window

    private func makeWindowIfNeeded() {
        guard overlayWindow == nil else { return }

        let w = NSWindow(
            contentRect: menuBarFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.backgroundColor = .black
        w.isOpaque = true
        w.hasShadow = false
        // One level above the status bar — sits on top of all menu-bar items.
        w.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        // Click-through: real menu-bar items below are still hittable.
        w.ignoresMouseEvents = true
        // Stay on every Space and slide into full-screen spaces too.
        w.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                .ignoresCycle, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        overlayWindow = w
    }

    private var menuBarFrame: NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        // screen.frame.maxY            = top of physical display
        // screen.visibleFrame.maxY     = bottom edge of the menu bar
        // The difference is the exact height the system reserves for the menu
        // bar — covers the notch on MacBook Pro without any hardcoded values.
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return NSRect(x: screen.frame.minX,
                      y: screen.visibleFrame.maxY,
                      width: screen.frame.width,
                      height: menuBarHeight)
    }

    private func updateVisibility() {
        // Always called on main thread (callers guarantee this).
        if isActive && !revealedByHover {
            overlayWindow?.setFrame(menuBarFrame, display: false)
            overlayWindow?.orderFrontRegardless()
        } else {
            overlayWindow?.orderOut(nil)
        }
    }

    @objc private func screensChanged() {
        guard isActive else { return }
        DispatchQueue.main.async { [self] in
            overlayWindow?.setFrame(menuBarFrame, display: true)
        }
    }

    // MARK: - Hover tracking

    private func startHoverTracking() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.evaluateHover()
        }
    }

    private func stopHoverTracking() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    private func evaluateHover() {
        guard isActive else { return }
        guard let screen = NSScreen.main else { return }
        // Reveal when cursor enters the overlay zone — threshold matches the
        // bottom edge of the menu bar (visibleFrame.maxY).
        let inZone = NSEvent.mouseLocation.y >= screen.visibleFrame.maxY
        guard inZone != revealedByHover else { return }
        revealedByHover = inZone
        updateVisibility()
    }
}
