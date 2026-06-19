import SwiftUI
import AppKit

// MARK: - App lifecycle
//
// Wires together the status item, popover, hotkey, polling timer and login
// window. Rendering and the global hotkey live in their own controllers; this
// class is the coordinator.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusController: StatusItemController!
    private var popover: NSPopover!
    private var usageManager: UsageManager!
    private var hotKeyManager: HotKeyManager!
    private var eventMonitor: Any?
    private var refreshTimer: Timer?
    private var loginWindowController: LoginWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Status bar item (variable length for the compact "spark + %" display).
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusController = StatusItemController(statusItem: statusItem)

        if let button = statusItem.button {
            statusController.update(percentage: nil)   // neutral until first data
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
            button.appearsDisabled = false
            button.isEnabled = true
        }

        usageManager = UsageManager(delegate: self)
        // Reflect any cached snapshot immediately.
        usageManager.updateStatusBar()

        // Popover. The hosting controller drives the popover size from SwiftUI's
        // intrinsic content size (macOS 13+), so the popover is sized correctly
        // the moment it appears and stays anchored to the status item. (Resizing
        // the contentSize *after* showing — the old approach — left the popover
        // detached from the menu-bar icon.)
        popover = NSPopover()
        popover.behavior = .transient
        let hosting = NSHostingController(rootView: UsageView(usageManager: usageManager))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        // Ask for notification permission once, up front.
        NotificationService.requestAuthorization()

        // Initial fetch + self-rescheduling poll (interval comes from settings,
        // and tightens automatically near a limit).
        usageManager.fetchUsage()
        scheduleNextFetch()

        // Global ⌘U.
        hotKeyManager = HotKeyManager(onTrigger: { [weak self] in self?.togglePopover() })
        if usageManager.shortcutEnabled {
            hotKeyManager.register()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregister()
        refreshTimer?.invalidate()
    }

    // MARK: Polling

    /// (Re)arm the refresh timer using the manager's current interval. Called
    /// after each fetch (so adaptive intervals take effect) and when the user
    /// changes the configured interval.
    func rescheduleFetch() {
        scheduleNextFetch()
    }

    private func scheduleNextFetch() {
        refreshTimer?.invalidate()
        let interval = usageManager.nextRefreshSeconds()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.usageManager.fetchUsage()
                self.scheduleNextFetch()
            }
        }
    }

    // MARK: Hotkey

    func setShortcutEnabled(_ enabled: Bool) {
        hotKeyManager.setEnabled(enabled)
    }

    // MARK: Status icon (called by UsageManager)

    func updateStatusIcon(percentage: Int?) {
        statusController.update(percentage: percentage)
    }

    // MARK: Popover / menu

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            let toggleItem = NSMenuItem(title: "Toggle Usage (⌘U)", action: #selector(togglePopover), keyEquivalent: "u")
            toggleItem.keyEquivalentModifierMask = .command
            menu.addItem(toggleItem)
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit Claudometer", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    @objc func togglePopover() {
        popover.isShown ? closePopover() : openPopover()
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        usageManager.updatePercentages()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Close when the user clicks outside the popover.
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover.isShown == true { self?.closePopover() }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    @objc func showLogin() {
        closePopover()
        if loginWindowController == nil {
            loginWindowController = LoginWindowController(onCapture: { [weak self] cookieHeader in
                guard let self = self else { return }
                self.usageManager.saveSessionCookie(cookieHeader)
                self.usageManager.fetchUsage()
                self.loginWindowController = nil
            })
        }
        loginWindowController?.present()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Entry point

@main
struct Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
