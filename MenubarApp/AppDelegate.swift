import Cocoa
import SwiftUI

// MARK: - Menu item container

/// Wraps any SwiftUI view inside an NSMenuItem.
/// `acceptsFirstMouse` → true so Toggle/Button fire on the very first click.
final class MenuItemContainerView: NSView {
    private let hosting: NSHostingView<AnyView>

    init<V: View>(_ content: V, width: CGFloat? = nil) {
        hosting = NSHostingView(rootView: AnyView(content))
        let fitting = hosting.fittingSize
        let w = width ?? fitting.width
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: fitting.height))
        hosting.frame = bounds
        addSubview(hosting)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var allowsVibrancy: Bool { false }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PLAYGROUNDS"] != "1" else { return }
        MenuBarManager.shared.restoreState()
        setupMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MenuBarManager.shared.cleanup()
    }

    // MARK: Setup

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let btn = statusItem.button else { return }
        btn.image = NSImage(systemSymbolName: "menubar.rectangle",
                            accessibilityDescription: "Menubar App")

        let mgr = MenuBarManager.shared

        // About item
        let aboutItem = NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        aboutItem.target = self
        quitItem.target = self
        
        menu = NSMenu()
        menu.autoenablesItems = false

        // Pre-measure so the menu opens at a fixed width regardless of which
        // sections are expanded.
        let durationContent = MenuItemContainerView(DurationView().environmentObject(mgr))
        let fixedWidth = max(durationContent.frame.width, 310)
        durationContent.setFrameSize(NSSize(width: fixedWidth, height: durationContent.frame.height))

        let settingsContent = MenuItemContainerView(
            SettingsView(width: fixedWidth).environmentObject(mgr)
        )

        // ── Menu Bar toggle (top-level) ───────────────────────────
        let toggleItem = NSMenuItem()
        toggleItem.view = MenuItemContainerView(
            MenuBarToggleView(width: fixedWidth).environmentObject(mgr)
        )
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        // ── Duration ──────────────────────────────────────────────
        addDisclosureSection(title: "Duration", contents: [durationContent], width: fixedWidth)

        // ── Settings ──────────────────────────────────────────────
        addDisclosureSection(title: "Settings", contents: [settingsContent], width: fixedWidth)

        // ── Actions ───────────────────────────────────────────────
        menu.addItem(.separator())
        menu.addItem(aboutItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func showAbout() {
        AboutWindowController.shared.show()
    }

    /// Appends a disclosure header followed by N (initially hidden) content
    /// items. Clicking the header expands/collapses all content rows inline.
    private func addDisclosureSection(title: String, contents: [NSView], width: CGFloat) {
        let contentItems: [NSMenuItem] = contents.map { view in
            let item = NSMenuItem()
            item.view = view
            item.isHidden = true
            return item
        }

        let headerItem = NSMenuItem()
        headerItem.view = DisclosureHeaderView(title: title, targets: contentItems, width: width)

        menu.addItem(headerItem)
        contentItems.forEach { menu.addItem($0) }
    }
}

// MARK: - Disclosure header

/// Clickable header row that toggles the visibility of an associated
/// content menu item without dismissing the enclosing menu.
final class DisclosureHeaderView: NSView {
    private let targets: [NSMenuItem]
    private let titleLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var expanded = false

    init(title: String, targets: [NSMenuItem], width: CGFloat) {
        self.targets = targets
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))

        titleLabel.font = .menuFont(ofSize: 0)
        titleLabel.stringValue = title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        chevron.image = NSImage(systemSymbolName: "chevron.right",
                                accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(chevron)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 6),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var allowsVibrancy: Bool { false }

    override func mouseDown(with event: NSEvent) {
        expanded.toggle()
        targets.forEach { $0.isHidden = !expanded }
        chevron.image = NSImage(
            systemSymbolName: expanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
    }
}

// MARK: - NSMenu convenience

private extension NSMenu {
    /// Wraps a SwiftUI view in a MenuItemContainerView and appends it.
    func addItem<V: View>(containing view: V) {
        let container = MenuItemContainerView(view)
        let item = NSMenuItem()
        item.view = container
        addItem(item)
    }
}
