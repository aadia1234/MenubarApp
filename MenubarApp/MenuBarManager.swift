import AppKit

// MARK: - Enums

enum HideMode: String {
    case off
    case always               // overlay always — regardless of context
    case desktopOnly          // overlay on desktop (not in full-screen)
    case fullScreenOnly       // overlay in full-screen (not on desktop)
}

enum HideDuration: String, CaseIterable, Equatable {
    case forever = "forever"
    case min15   = "15m"
    case min30   = "30m"
    case min45   = "45m"
    case hour1   = "1h"
    case hour4   = "4h"
    case hour8   = "8h"

    var label: String {
        switch self {
        case .forever: return "∞"
        case .min15:   return "15"
        case .min30:   return "30"
        case .min45:   return "45"
        case .hour1:   return "01"
        case .hour4:   return "04"
        case .hour8:   return "08"
        }
    }

    var menuTitle: String {
        switch self {
        case .forever: return "Forever"
        case .min15:   return "15 Minutes"
        case .min30:   return "30 Minutes"
        case .min45:   return "45 Minutes"
        case .hour1:   return "1 Hour"
        case .hour4:   return "4 Hours"
        case .hour8:   return "8 Hours"
        }
    }

    /// nil = no expiry (forever)
    var seconds: TimeInterval? {
        switch self {
        case .forever: return nil
        case .min15:   return 15 * 60
        case .min30:   return 30 * 60
        case .min45:   return 45 * 60
        case .hour1:   return 1  * 3600
        case .hour4:   return 4  * 3600
        case .hour8:   return 8  * 3600
        }
    }
}

// MARK: - Manager

final class MenuBarManager: ObservableObject {
    static let shared = MenuBarManager()

    /// Fresh instance with no side effects — safe to use in Xcode previews.
    #if DEBUG
    static var preview: MenuBarManager { MenuBarManager() }
    #endif

    @Published private(set) var hideMode:     HideMode     = .off
    @Published private(set) var hideDuration: HideDuration = .forever

    private var durationTimer: Timer?
    private var observers: [Any] = []

    private init() {}

    // MARK: Lifecycle

    func restoreState() {
        let savedMode = HideMode(
            rawValue: UserDefaults.standard.string(forKey: "mbapp.hideMode") ?? "off"
        ) ?? .off
        let savedDuration = HideDuration(
            rawValue: UserDefaults.standard.string(forKey: "mbapp.hideDuration") ?? "forever"
        ) ?? .forever

        hideMode     = savedMode
        hideDuration = savedDuration

        setupObservers()

        if savedMode != .off {
            // Give the system a moment to settle before showing the overlay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.applyOverlayForCurrentContext()
            }
            startDurationTimer()
        }
    }

    func cleanup() {
        stopAllTimers()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        MenuBarOverlay.shared.deactivate()
    }

    // MARK: Public controls

    func setHideMode(_ mode: HideMode) {
        // Tapping the active mode turns it off
        if mode == hideMode, mode != .off {
            deactivate()
            return
        }

        hideMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "mbapp.hideMode")
        stopAllTimers()
        applyOverlayForCurrentContext()

        if mode != .off { startDurationTimer() }
    }

    func setHideDuration(_ duration: HideDuration) {
        hideDuration = duration
        UserDefaults.standard.set(duration.rawValue, forKey: "mbapp.hideDuration")
        stopDurationTimer()
        if hideMode != .off { startDurationTimer() }
    }

    // MARK: Overlay logic

    /// Decides whether the overlay should be up right now.
    /// MUST be called on the main thread — NSWindow creation/ordering is not thread-safe.
    private func applyOverlayForCurrentContext() {
        assert(Thread.isMainThread, "applyOverlayForCurrentContext must be called on main thread")

        switch hideMode {
        case .off:
            MenuBarOverlay.shared.deactivate()

        case .always:
            MenuBarOverlay.shared.activate()

        case .desktopOnly:
            // Show overlay on desktop; full-screen apps already cover the whole
            // screen, so the overlay would be invisible/redundant there.
            if isInFullScreenSpace() {
                MenuBarOverlay.shared.deactivate()
            } else {
                MenuBarOverlay.shared.activate()
            }

        case .fullScreenOnly:
            if isInFullScreenSpace() {
                MenuBarOverlay.shared.activate()
            } else {
                MenuBarOverlay.shared.deactivate()
            }

        }
    }

    /// Returns true when the frontmost app has a window that fills the entire
    /// main display — scoped to frontmost PID to avoid false positives from
    /// maximised windows on a second monitor with the same dimensions.
    private func isInFullScreenSpace() -> Bool {
        guard let screen = NSScreen.main,
              let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        else { return false }

        let W = screen.frame.width
        let H = screen.frame.height

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        return list.contains { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  pid == frontPID,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let b = info[kCGWindowBounds as String] as? [String: Any],
                  let w = b["Width"]  as? CGFloat,
                  let h = b["Height"] as? CGFloat
            else { return false }
            return w >= W - 1 && h >= H - 1
        }
    }

    // MARK: Private helpers

    private func deactivate() {
        hideMode = .off
        UserDefaults.standard.set(HideMode.off.rawValue, forKey: "mbapp.hideMode")
        stopAllTimers()
        MenuBarOverlay.shared.deactivate()
    }

    private func startDurationTimer() {
        guard let secs = hideDuration.seconds else { return }
        durationTimer = Timer.scheduledTimer(withTimeInterval: secs, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.deactivate() }
        }
        RunLoop.main.add(durationTimer!, forMode: .common)
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func stopAllTimers() {
        stopDurationTimer()
    }

    private func setupObservers() {
        // Both observers fire on .main so it's safe to call applyOverlayForCurrentContext.
        let spaceObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.applyOverlayForCurrentContext() }

        let appObs = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.applyOverlayForCurrentContext() }

        observers = [spaceObs, appObs]
    }

}
