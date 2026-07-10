import AppKit
import Combine
import SwiftUI

/// AppKit shell: status item with live usage text, floating desktop widget window,
/// and context menu on right-click. Runs as an accessory app (no Dock icon).
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?

    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            Diagnose.run()
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var statusItem: NSStatusItem?
    private var widgetWindow: WidgetWindow?
    private var store: UsageStore?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let fontCount = FiraCode.registerFonts()
        FileHandle.standardError.write(
            Data("[ConductorAgentWatch] Registered \(fontCount) Fira Code font face(s)\n".utf8)
        )

        let store = UsageStore()
        self.store = store

        // Create status bar item
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        if let button = statusItem.button {
            button.title = "--"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            
            // Set the app icon in the status bar button
            if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 16, height: 16)
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageLeft
            }
        }

        // Initialize and show the widget window on launch
        let widgetWindow = WidgetWindow(store: store)
        self.widgetWindow = widgetWindow
        if store.settings.showDesktopWidget {
            widgetWindow.orderFrontRegardless()
        }

        // Bind menu bar title updates
        store.$menuBarTitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title in
                self?.statusItem?.button?.title = title
            }
            .store(in: &cancellables)

        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.stop()
    }

    // MARK: - Status item interactions

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            toggleWidget()
        }
    }

    private func toggleWidget() {
        guard let widgetWindow else { return }
        let makeVisible = !widgetWindow.isVisible
        if makeVisible {
            NSApp.activate(ignoringOtherApps: true)
            widgetWindow.orderFrontRegardless()
        } else {
            widgetWindow.orderOut(nil)
        }
        if let store = store {
            var s = store.settings
            s.showDesktopWidget = makeVisible
            store.updateSettings(s)
        }
    }

    func updateWidgetVisibility() {
        guard let widgetWindow, let store = store else { return }
        if store.settings.showDesktopWidget {
            widgetWindow.orderFrontRegardless()
        } else {
            widgetWindow.orderOut(nil)
        }
    }

    private func showContextMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Conductor AgentWatch", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // Temporarily attach the menu so it pops up, then detach
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refresh() {
        store?.manualRefresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
