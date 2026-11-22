import AppKit
import Quartz

/// Shows a file in the Quick Look panel, then hands focus back to the app the link was clicked in.
/// While the preview is open: ⌘R shows the file in Finder, ⌘O opens it in its app.
/// (Some apps, like Craft, don't pass ⌥-clicks on, so this is the way to Finder there.)
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLook()

    private var url: URL?
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    /// Set when the preview closes because the file is handed to Finder or its app.
    private var handedOff = false

    func show(_ url: URL) {
        self.url = url
        handedOff = false
        // macOS often activates Linky before the link arrives, so use the app that was active before Linky.
        previousApp = AppDelegate.lastOtherApp

        AppDelegate.bringAppToFront()
        guard let panel = QLPreviewPanel.shared() else { return }
        attach(to: panel)
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installKeyMonitor()
    }

    func attach(to panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
    }

    // MARK: ⌘R / ⌘O in the preview

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let commandOnly = event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
            let key = event.charactersIgnoringModifiers?.lowercased()
            guard commandOnly, key == "r" || key == "o" else { return event }
            let handled = MainActor.assumeIsolated { QuickLook.shared.handleShortcut(key ?? "") }
            return handled ? nil : event
        }
    }

    /// ⌘R → show in Finder, ⌘O → open in its app. Returns false if no preview is showing.
    private func handleShortcut(_ key: String) -> Bool {
        guard let url, QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible else { return false }
        handOff {
            if key == "r" { NSWorkspace.shared.activateFileViewerSelecting([url]) } else { NSWorkspace.shared.open(url) }
        }
        return true
    }

    private func handOff(_ action: () -> Void) {
        handedOff = true
        QLPreviewPanel.shared().close()
        action()
    }

    // MARK: QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { url == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { url as NSURL? }
    }

    // MARK: Closing: back to where the link was clicked

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
            url = nil
            // After ⌘R / ⌘O, Finder or the file's app should stay in front.
            if !handedOff, let app = previousApp, !app.isTerminated {
                NSApp.yieldActivation(to: app)
                app.activate()
            }
            previousApp = nil
            handedOff = false
        }
    }
}
