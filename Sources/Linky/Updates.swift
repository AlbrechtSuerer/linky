import AppKit

/// Checks GitHub for a newer release – only when the user asks for it. Nothing runs in the background.
@MainActor
enum Updates {
    private static let latestRelease = URL(string: "https://api.github.com/repos/AlbrechtSuerer/linky/releases/latest")!
    private static var isChecking = false

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
    }

    static func check() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                var request = URLRequest(url: latestRelease, timeoutInterval: 15)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))

                if isVersion(latest, newerThan: currentVersion) {
                    offerUpdate(to: latest, page: release.html_url)
                } else {
                    Toast.show("Linky is up to date", detail: "Version \(currentVersion)", symbol: "checkmark")
                }
            } catch {
                Toast.show("Couldn’t check for updates", detail: "Please try again later.",
                           symbol: "wifi.exclamationmark", style: .warning)
            }
        }
    }

    /// Compares dotted versions numerically: 1.10 is newer than 1.9, 1.3.1 is newer than 1.3.
    nonisolated static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func offerUpdate(to version: String, page: URL) {
        AppDelegate.bringAppToFront()
        let alert = NSAlert()
        alert.messageText = "Linky \(version) is available"
        alert.informativeText = "You have version \(currentVersion). Download Linky.zip, unzip it and replace Linky in your Applications folder. Your links are kept."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(page)
        }
    }
}
