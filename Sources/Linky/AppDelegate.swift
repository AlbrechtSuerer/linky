import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?

    private var statusItem: NSStatusItem!
    private var copyItem: NSMenuItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        setupStatusItem()

        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        HotKey.shared.handler = { Linky.copyLinksForFinderSelection() }
        Preferences.shared.onShortcutChange = { [weak self] in self?.updateMenuShortcut() }
        Preferences.shared.applyShortcut()
    }

    // MARK: linky:// links

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            switch url.host {
            case "settings":
                showSettings(page: .general)
            case "check-updates":
                Updates.check()
            case "links":
                showSettings(page: .links)
            case "copy":
                // linky://copy?path=/a&path=/b – or without paths: the current Finder selection.
                let paths = query.filter { $0.name == "path" }.compactMap(\.value)
                    .filter { FileManager.default.fileExists(atPath: $0) }
                if paths.isEmpty {
                    Linky.copyLinksForFinderSelection()
                } else {
                    Linky.copyLinks(for: paths.map { URL(fileURLWithPath: $0) })
                }
            case "refresh":
                // Re-checks all links and saves moved paths, so readers of links.json see current locations.
                LinkStore.shared.refreshStatus()
            case "copy-id":
                // linky://copy-id?id=… – copies an existing link again (used by the Raycast extension).
                if let id = query.first(where: { $0.name == "id" })?.value,
                   let entry = LinkStore.shared.entries[id] {
                    Linky.copyAgain(entry)
                }
            default:
                Linky.open(url)
            }
        }
    }

    /// Opening Linky again (e.g. from Spotlight) shows its settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(page: .general)
        return false
    }

    // MARK: Finder › Dienste › „Linky-Link kopieren“

    @objc func copyLinkyLink(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        Linky.copyLinks(for: urls)
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "link", accessibilityDescription: "Linky")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// The menu is rebuilt every time it opens, so "recent" is always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let store = LinkStore.shared
        store.refreshStatus()
        menu.removeAllItems()

        let copy = NSMenuItem(title: "Copy Link to Finder Selection", action: #selector(copyFromMenu), keyEquivalent: "")
        copy.target = self
        menu.addItem(copy)
        copyItem = copy
        updateMenuShortcut()

        let recent = store.recent(6)
        if !recent.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Recent"))
            for entry in recent {
                let missing = store.isMissing(entry)
                let icon = menuIcon(for: entry, missing: missing)

                let item = NSMenuItem(title: entry.name, action: #selector(recentClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.id
                item.image = icon
                item.toolTip = missing ? "File not found – click to relink"
                                       : "Click to copy the link · ⌥-click to show it in Finder"
                menu.addItem(item)

                if !missing {
                    let reveal = NSMenuItem(title: "Show \(entry.name) in Finder", action: #selector(revealClicked(_:)), keyEquivalent: "")
                    reveal.target = self
                    reveal.representedObject = entry.id
                    reveal.image = icon
                    reveal.isAlternate = true
                    reveal.keyEquivalentModifierMask = .option
                    menu.addItem(reveal)
                }
            }
        }

        menu.addItem(.separator())
        if !store.missing.isEmpty {
            let n = store.missing.count
            let broken = NSMenuItem(title: n == 1 ? "1 Broken Link…" : "\(n) Broken Links…",
                                    action: #selector(showLinks), keyEquivalent: "")
            broken.target = self
            broken.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(broken)
        }
        let all = NSMenuItem(title: "All Links…", action: #selector(showLinks), keyEquivalent: "")
        all.target = self
        menu.addItem(all)

        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)

        let settings = NSMenuItem(title: "Settings…", action: #selector(showGeneralSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Linky", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func menuIcon(for entry: LinkStore.Entry, missing: Bool) -> NSImage? {
        if missing {
            return NSImage(systemSymbolName: "questionmark.folder", accessibilityDescription: nil)
        }
        let icon = NSWorkspace.shared.icon(forFile: entry.path).copy() as? NSImage
        icon?.size = NSSize(width: 16, height: 16)
        return icon
    }

    private func updateMenuShortcut() {
        guard let copyItem else { return }
        if let s = Preferences.shared.shortcut, s.key.count == 1 {
            copyItem.keyEquivalent = s.key.lowercased()
            copyItem.keyEquivalentModifierMask = s.modifierFlags
        } else {
            copyItem.keyEquivalent = ""
            copyItem.keyEquivalentModifierMask = []
        }
    }

    private func entry(for item: NSMenuItem) -> LinkStore.Entry? {
        (item.representedObject as? String).flatMap { LinkStore.shared.entries[$0] }
    }

    @objc private func copyFromMenu() {
        Linky.copyLinksForFinderSelection()
    }

    @objc private func recentClicked(_ item: NSMenuItem) {
        guard let entry = entry(for: item) else { return }
        if LinkStore.shared.isMissing(entry) {
            showSettings(page: .links)
        } else {
            Linky.copyAgain(entry)
        }
    }

    @objc private func revealClicked(_ item: NSMenuItem) {
        if let entry = entry(for: item) { Linky.reveal(entry) }
    }

    @objc private func showLinks() { showSettings(page: .links) }
    @objc private func showGeneralSettings() { showSettings(page: .general) }
    @objc private func checkForUpdates() { Updates.check() }

    // MARK: Settings window

    func showSettings(page: SettingsNav.Page) {
        let nav = SettingsNav.shared
        nav.page = page
        if page == .links {
            nav.linksExpanded = true
            nav.focusLinksRequest += 1
        }
        LinkStore.shared.refreshStatus()

        if settingsWindow == nil {
            let host = NSHostingView(rootView: SettingsView())
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: SettingsView.size),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Linky"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.center()
            settingsWindow = window
        }
        // Wait until the status menu has closed, then bring the window forward.
        DispatchQueue.main.async { [weak self] in
            self?.bringSettingsToFront()
        }
    }

    /// Since macOS 14, `NSApp.activate()` is only a request that the frontmost app may turn down,
    /// which left an already open settings window behind other apps. So: ask the frontmost app to
    /// hand over activation, and put the window in front regardless.
    private func bringSettingsToFront() {
        guard let window = settingsWindow else { return }
        Self.bringAppToFront()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// Asks the frontmost app to hand over activation (a plain `NSApp.activate()` may be turned down).
    static func bringAppToFront() {
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            NSRunningApplication.current.activate(from: front, options: [])
        } else {
            NSApp.activate()
        }
    }
}
