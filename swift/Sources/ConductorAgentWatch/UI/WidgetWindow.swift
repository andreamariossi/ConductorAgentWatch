import AppKit
import SwiftUI
import Combine

class WidgetWindow: NSPanel, NSWindowDelegate {
    private var cancellables = Set<AnyCancellable>()
    private let store: UsageStore
    private var lastScale: AppSettings.WidgetScale?
    
    init(store: UsageStore) {
        self.store = store
        self.lastScale = store.settings.widgetScale
        
        let initialWidth = store.settings.widgetWidth
        let initialHeight = store.settings.widgetHeight
        
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: initialWidth, height: initialHeight),
            styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Conductor AgentWatch"
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .normal
        self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        self.isMovableByWindowBackground = true
        self.hasShadow = true
        self.delegate = self
        
        // Hide standard window decorations but keep resizability
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        
        let controller = NSHostingController(
            rootView: RootView().environmentObject(store)
        )
        self.contentViewController = controller
        
        // Position at the bottom-right of the screen
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.origin.x + screenRect.size.width - initialWidth - 40
            let y = screenRect.origin.y + 40
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // Listen to settings changes to dynamically resize the widget on preset change
        store.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSettings in
                guard let self = self else { return }
                if self.lastScale != newSettings.widgetScale {
                    self.lastScale = newSettings.widgetScale
                    self.updateSize(for: newSettings.widgetScale)
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateSize(for scale: AppSettings.WidgetScale) {
        let newWidth = scale.width
        let newHeight = scale.height
        
        let currentFrame = self.frame
        guard currentFrame.size.width != newWidth || currentFrame.size.height != newHeight else { return }
        
        let currentTopY = currentFrame.origin.y + currentFrame.size.height
        let newX = currentFrame.origin.x + currentFrame.size.width - newWidth
        let newY = currentTopY - newHeight
        
        let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
        self.setFrame(newFrame, display: true, animate: true)
    }
    
    // MARK: - NSWindowDelegate
    
    func windowDidEndLiveResize(_ notification: Notification) {
        let size = self.frame.size
        // Only update settings if the size differs from the saved values
        guard abs(store.settings.widgetWidth - size.width) > 1 || 
              abs(store.settings.widgetHeight - size.height) > 1 else { return }
        
        var s = store.settings
        s.widgetWidth = size.width
        s.widgetHeight = size.height
        store.updateSettings(s)
    }
    
    override var canBecomeKey: Bool {
        return true
    }
}
