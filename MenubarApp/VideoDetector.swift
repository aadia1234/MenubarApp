import AppKit
import IOKit.pwr_mgt

final class VideoDetector {

    // MARK: - Full-screen detection

    func isAnyAppFullScreen() -> Bool {
        guard let screen = NSScreen.main else { return false }
        let screenSize = screen.frame.size

        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for win in list {
            guard
                let layer = win[kCGWindowLayer as String] as? Int, layer == 0,
                let bounds = win[kCGWindowBounds as String] as? [String: CGFloat],
                let w = bounds["Width"], let h = bounds["Height"]
            else { continue }

            if abs(w - screenSize.width) < 2 && abs(h - screenSize.height) < 2 {
                return true
            }
        }
        return false
    }

    // MARK: - Video detection

    /// True when a known video player is frontmost AND that specific process
    /// holds a display-sleep-prevention assertion (i.e. is actively playing).
    /// Per-process checking ensures:
    ///  • switching to any non-player app immediately returns false
    ///  • pausing / stopping releases the browser's assertion → returns false
    func isVideoPlaying() -> Bool {
        guard frontAppIsVideoPlayer() else { return false }
        return frontAppHoldsDisplayAssertion()
    }

    // MARK: - Per-process assertion check

    // IOPMCopyAssertionsByType is in IOKit but isn't bridged into Swift's module
    // overlay, so we load it at runtime via dlopen/dlsym.
    private typealias AssertionsByTypeFn =
        @convention(c) (CFString, UnsafeMutablePointer<Unmanaged<CFDictionary>?>) -> IOReturn

    private static let assertionsByTypeFn: AssertionsByTypeFn? = {
        let lib = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)
        guard let sym = dlsym(lib, "IOPMCopyAssertionsByType") else { return nil }
        return unsafeBitCast(sym, to: AssertionsByTypeFn.self)
    }()

    /// Checks whether the frontmost app's PID is holding a display-sleep assertion.
    /// Falls back to the aggregate check if the symbol isn't available.
    private func frontAppHoldsDisplayAssertion() -> Bool {
        guard let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        else { return false }

        guard let fn = Self.assertionsByTypeFn else {
            // Symbol unavailable — fall back to aggregate (less accurate)
            return hasAggregateDisplayAssertion()
        }

        let types: [CFString] = [
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            kIOPMAssertionTypeNoDisplaySleep as CFString
        ]

        for assertionType in types {
            var raw: Unmanaged<CFDictionary>?
            guard fn(assertionType, &raw) == kIOReturnSuccess,
                  let dict = raw?.takeRetainedValue() as? [String: [[String: Any]]],
                  let list = dict[assertionType as String] else { continue }

            let match = list.contains { info in
                (info["AssertionPID"] as? Int).map { pid_t($0) == frontPID } ?? false
            }
            if match { return true }
        }
        return false
    }

    /// Aggregate fallback: any process holds a display-sleep assertion.
    private func hasAggregateDisplayAssertion() -> Bool {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&raw) == kIOReturnSuccess,
              let dict = raw?.takeRetainedValue() as? [String: Any] else { return false }
        for key in [kIOPMAssertionTypePreventUserIdleDisplaySleep as String,
                    kIOPMAssertionTypeNoDisplaySleep as String] {
            if let v = dict[key] as? Int, v > 0 { return true }
        }
        return false
    }

    // MARK: - Helpers

    private func frontAppIsVideoPlayer() -> Bool {
        guard let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        let players: Set<String> = [
            "com.apple.Safari",
            "com.google.Chrome",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "org.videolan.vlc",
            "com.colliderli.iina",
            "com.apple.QuickTimePlayerX",
            "com.apple.TV",
            "tv.plex.plex",
            "com.plex.plexamp",
            "com.amazon.Amazon-Video",
            "com.disney.disneyplus",
            "com.netflix.Netflix",
        ]
        return players.contains(bid)
    }
}
