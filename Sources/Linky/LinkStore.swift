import Foundation
import Observation

/// Maps short link ids to macOS bookmarks, so links keep working after a file is moved or renamed.
/// Stored as plain JSON in ~/Library/Application Support/Linky/links.json.
@MainActor
@Observable
final class LinkStore {
    static let shared = LinkStore()

    struct Entry: Codable, Identifiable, Equatable {
        let id: String
        var bookmark: Data
        var path: String
        let created: Date
        var lastUsed: Date?

        /// When the link was last created or copied – drives "recent".
        var used: Date { lastUsed ?? created }
        var name: String { path == "/" ? "Macintosh HD" : (path as NSString).lastPathComponent }
        var folder: String {
            // /private/tmp and /tmp are the same place; compare without the prefix.
            let strip = { (s: String) in s.hasPrefix("/private/") ? String(s.dropFirst(8)) : s }
            let dir = strip((path as NSString).deletingLastPathComponent)
            let home = strip(NSHomeDirectory())
            if dir == home || dir.hasPrefix(home + "/") { return "~" + dir.dropFirst(home.count) }
            return dir
        }
    }

    private(set) var entries: [String: Entry] = [:]
    /// Ids whose file could not be found at the last check.
    private(set) var missing: Set<String> = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var dirty = false

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Linky", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("links.json")
        load()
    }

    // MARK: Reading

    /// All links, most recently used first.
    var all: [Entry] { entries.values.sorted { $0.used > $1.used } }

    func recent(_ limit: Int) -> [Entry] { Array(all.prefix(limit)) }

    func isMissing(_ entry: Entry) -> Bool { missing.contains(entry.id) }

    // MARK: Creating

    /// Returns the existing id for this file, or creates a new one. Either way it counts as "used now".
    func id(for url: URL) throws -> String {
        let path = url.standardizedFileURL.path
        if let existing = entries.values.first(where: { $0.path == path }) {
            entries[existing.id]?.lastUsed = Date()
            save()
            return existing.id
        }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        var id = Self.newID()
        while entries[id] != nil { id = Self.newID() }
        let now = Date()
        entries[id] = Entry(id: id, bookmark: bookmark, path: path, created: now, lastUsed: now)
        save()
        return id
    }

    func touch(_ id: String) {
        entries[id]?.lastUsed = Date()
        save()
    }

    // MARK: Resolving

    /// Finds the file behind a link: first via its bookmark (follows moves/renames), then via the stored path.
    func resolve(id: String?, fallbackPath: String?) -> URL? {
        if let id, entries[id] != nil {
            let url = locate(id, allowMounting: true)
            if dirty { save() }
            if let url { missing.remove(id); return url }
            missing.insert(id)
        }
        if let fallbackPath, FileManager.default.fileExists(atPath: fallbackPath) {
            return URL(fileURLWithPath: fallbackPath)
        }
        return nil
    }

    /// Re-checks every link and updates `missing` (and paths of moved files).
    func refreshStatus() {
        var gone = Set<String>()
        for id in Array(entries.keys) where locate(id, allowMounting: false) == nil {
            gone.insert(id)
        }
        if gone != missing { missing = gone }
        if dirty { save() }
    }

    // MARK: Editing

    /// Points an existing link at another file. Everywhere the link was pasted, it now opens the new file.
    func relink(_ id: String, to url: URL) throws {
        guard var entry = entries[id] else { return }
        entry.bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        entry.path = url.standardizedFileURL.path
        entry.lastUsed = Date()
        entries[id] = entry
        missing.remove(id)
        save()
    }

    func remove(_ id: String) {
        entries[id] = nil
        missing.remove(id)
        save()
    }

    // MARK: Private

    private func locate(_ id: String, allowMounting: Bool) -> URL? {
        guard var entry = entries[id] else { return nil }
        let fm = FileManager.default
        var options: URL.BookmarkResolutionOptions = [.withoutUI]
        if !allowMounting { options.insert(.withoutMounting) }

        var stale = false
        if let url = try? URL(resolvingBookmarkData: entry.bookmark, options: options,
                              relativeTo: nil, bookmarkDataIsStale: &stale),
           fm.fileExists(atPath: url.path), !Self.isInTrash(url.path) {
            if stale || url.path != entry.path {
                entry.path = url.path
                if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    entry.bookmark = fresh
                }
                entries[id] = entry
                dirty = true
            }
            return url
        }
        if fm.fileExists(atPath: entry.path), !Self.isInTrash(entry.path) {
            return URL(fileURLWithPath: entry.path)
        }
        return nil
    }

    private static func isInTrash(_ path: String) -> Bool {
        path.contains("/.Trash/") || path.contains("/.Trashes/")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let list = try? decoder.decode([Entry].self, from: data) {
            entries = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    private func save() {
        dirty = false
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let list = entries.values.sorted { $0.created < $1.created }
        if let data = try? encoder.encode(list) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func newID() -> String {
        let chars = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<10).map { _ in chars.randomElement()! })
    }
}
