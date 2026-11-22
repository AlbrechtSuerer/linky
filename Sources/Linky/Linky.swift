import AppKit

/// The two things Linky does: copy links, open links.
@MainActor
enum Linky {
    static let scheme = "linky"
    static let supportURL = URL(string: "https://buymeacoffee.com/trugschluss")!

    // MARK: Copy

    static func copyLinksForFinderSelection() {
        switch FinderSelection.read() {
        case .success(let urls):
            copyLinks(for: urls)
        case .failure(.notAllowed):
            Toast.show("Linky needs access to Finder",
                       detail: "System Settings › Privacy & Security › Automation",
                       symbol: "lock", style: .warning)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        case .failure(.other(let message)):
            Toast.show("Couldn’t read the Finder selection", detail: message, symbol: "exclamationmark.triangle", style: .warning)
        }
    }

    static func copyLinks(for urls: [URL]) {
        guard !urls.isEmpty else {
            Toast.show("Nothing selected", detail: "Select a file or folder in Finder.",
                       symbol: "cursorarrow.click", style: .warning)
            return
        }

        var links: [Clipboard.Link] = []
        for url in urls {
            do {
                let id = try LinkStore.shared.id(for: url)
                links.append(.init(name: LinkStore.Entry.displayName(forPath: url.path), url: makeURL(id: id, path: url.path)))
            } catch {
                Toast.show("Couldn’t create link", detail: url.lastPathComponent,
                           symbol: "exclamationmark.triangle", style: .warning)
                return
            }
        }

        Clipboard.write(links, format: Preferences.shared.format)
        Toast.show(links.count == 1 ? "Link copied" : "\(links.count) links copied",
                   detail: links.count == 1 ? links[0].name : nil,
                   symbol: "link")
    }

    // MARK: Open

    static func open(_ url: URL) {
        guard url.scheme == scheme,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let id = comps.queryItems?.first { $0.name == "id" }?.value
        // The fallback path is stored relative to the home folder ("~/…"), so links carry no user name
        // and also work on another Mac with a different user name. Older links have an absolute path.
        let path = comps.queryItems?.first { $0.name == "p" }?.value.map { ($0 as NSString).expandingTildeInPath }

        guard let target = LinkStore.shared.resolve(id: id, fallbackPath: path) else {
            NSSound.beep()
            let known = id.flatMap { LinkStore.shared.entries[$0] } != nil
            Toast.show("File not found",
                       detail: known ? "You can relink it in Linky."
                                     : path.map { ($0 as NSString).lastPathComponent },
                       symbol: "questionmark.folder", style: .warning)
            if known { AppDelegate.shared?.showSettings(page: .links) }
            return
        }

        // ⌥-click (or linky://reveal) shows the file in Finder. Otherwise the "Click opens" setting decides,
        // and ⌘- or ⇧-click does the other one (Quick Look instead of opening, or the other way round).
        // Apps decide which modifier clicks they pass on: Craft passes ⌘ only, Apple Notes passes all.
        let flags = NSEvent.modifierFlags
        if comps.host == "reveal" || flags.contains(.option) {
            NSWorkspace.shared.activateFileViewerSelecting([target])
            return
        }
        var preview = comps.host == "quicklook" || Preferences.shared.clickAction == .quickLook
        if comps.host != "quicklook" && (flags.contains(.command) || flags.contains(.shift)) { preview.toggle() }
        if preview {
            QuickLook.shared.show(target)
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    // MARK: Existing links

    static func copyAgain(_ entry: LinkStore.Entry) {
        LinkStore.shared.touch(entry.id)
        Clipboard.write([.init(name: entry.name, url: makeURL(id: entry.id, path: entry.path))],
                        format: Preferences.shared.format)
        Toast.show("Link copied", detail: entry.name, symbol: "link")
    }

    static func reveal(_ entry: LinkStore.Entry) {
        if let url = LinkStore.shared.resolve(id: entry.id, fallbackPath: nil) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            Toast.show("File not found", detail: entry.name, symbol: "questionmark.folder", style: .warning)
        }
    }

    /// Lets the user pick a new file for a link. Every place the link was pasted then opens the new file.
    static func relink(_ entry: LinkStore.Entry) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Relink"
        panel.message = "Choose a new file for “\(entry.name)”"
        panel.directoryURL = nearestExistingFolder(of: entry.path)
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try LinkStore.shared.relink(entry.id, to: url)
            Toast.show("Link relinked", detail: url.lastPathComponent, symbol: "checkmark")
        } catch {
            Toast.show("Couldn’t relink", detail: error.localizedDescription,
                       symbol: "exclamationmark.triangle", style: .warning)
        }
    }

    private static func nearestExistingFolder(of path: String) -> URL {
        var dir = (path as NSString).deletingLastPathComponent
        while !dir.isEmpty, dir != "/", !FileManager.default.fileExists(atPath: dir) {
            dir = (dir as NSString).deletingLastPathComponent
        }
        return URL(fileURLWithPath: dir.isEmpty ? NSHomeDirectory() : dir, isDirectory: true)
    }

    // MARK: Helpers

    static func makeURL(id: String, path: String) -> URL {
        // Encode the fallback path tightly so the URL is also safe inside Markdown.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        let p = homeRelative(path).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "\(scheme)://open?id=\(id)&p=\(p)")!
    }

    /// "/Users/name/Documents/a.pdf" → "~/Documents/a.pdf". Paths outside the home folder stay absolute.
    /// (/private/tmp and /tmp are the same place, so they are compared without that prefix.)
    nonisolated static func homeRelative(_ path: String) -> String {
        let strip = { (s: String) in s.hasPrefix("/private/") ? String(s.dropFirst(8)) : s }
        let p = strip(path), home = strip(NSHomeDirectory())
        if p == home { return "~" }
        return p.hasPrefix(home + "/") ? "~" + p.dropFirst(home.count) : path
    }
}
