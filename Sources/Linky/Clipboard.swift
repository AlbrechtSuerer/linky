import AppKit

enum ClickAction: String, CaseIterable, Identifiable {
    case open, quickLook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "File"
        case .quickLook: "Quick Look"
        }
    }

    var subtitle: String {
        switch self {
        case .open: "Opens the file in its app. ⌘-click to preview it with Quick Look instead."
        case .quickLook: "Previews the file without leaving your notes. ⌘-click to open it instead."
        }
    }
}

enum LinkFormat: String, CaseIterable, Identifiable {
    case rich, markdown, url

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rich: "Linked file name"
        case .markdown: "Markdown"
        case .url: "URL only"
        }
    }

    var subtitle: String {
        switch self {
        case .rich: "Clickable file name – ideal for Craft, Notes and Mail."
        case .markdown: "[File](linky://…) – for Obsidian and Markdown editors."
        case .url: "Just the linky:// URL, without a name."
        }
    }
}

@MainActor
enum Clipboard {
    struct Link {
        let name: String
        let url: URL
    }

    static func write(_ links: [Link], format: LinkFormat) {
        let pb = NSPasteboard.general
        pb.clearContents()

        let markdown = links.map { "[\(escapeMarkdown($0.name))](\($0.url.absoluteString))" }.joined(separator: "\n")

        switch format {
        case .url:
            pb.setString(links.map(\.url.absoluteString).joined(separator: "\n"), forType: .string)

        case .markdown:
            pb.setString(markdown, forType: .string)

        case .rich:
            let html = links.map { "<a href=\"\(escapeHTML($0.url.absoluteString))\">\(escapeHTML($0.name))</a>" }
                .joined(separator: "<br>")
            pb.setString(html, forType: .html)

            let attributed = NSMutableAttributedString()
            for (i, link) in links.enumerated() {
                if i > 0 { attributed.append(NSAttributedString(string: "\n")) }
                attributed.append(NSAttributedString(string: link.name, attributes: [.link: link.url]))
            }
            if let rtf = try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                                              documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                pb.setData(rtf, forType: .rtf)
            }

            // Plain-text fallback: Markdown, which most editors turn into a link.
            pb.setString(markdown, forType: .string)
        }
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func escapeMarkdown(_ s: String) -> String {
        s.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
}
