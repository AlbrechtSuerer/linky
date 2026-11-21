import AppKit
import Observation
import SwiftUI

/// Lets the menu bar open Settings scrolled to the links.
@MainActor
@Observable
final class SettingsNav {
    static let shared = SettingsNav()

    enum Page { case general, links }

    var page: Page = .general
    var linksExpanded = false
    /// Bumped to ask an open settings window to scroll to the links.
    var focusLinksRequest = 0
}

struct SettingsView: View {
    static let size = NSSize(width: 640, height: 720)

    @Bindable var nav = SettingsNav.shared
    @Bindable var prefs = Preferences.shared

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HeaderCard(symbol: "link", title: "Linky",
                               subtitle: "Links to files and folders you can paste anywhere.")

                    SettingsSection("Shortcut",
                                    footer: "Creates links for whatever is selected in Finder – no matter which app is in front.") {
                        SettingsRow(title: "Copy link",
                                    subtitle: "Or right-click in Finder › Services.") {
                            ShortcutField(shortcut: $prefs.shortcut)
                        }
                    }

                    SettingsSection("Link") {
                        SettingsRow(title: "Format", subtitle: prefs.format.subtitle) {
                            Picker("", selection: $prefs.format) {
                                ForEach(LinkFormat.allCases) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                    }

                    SettingsSection("General",
                                    footer: "Tip: Hold ⌥ while clicking a link to show the file in Finder instead of opening it.") {
                        SettingsRow(title: "Open at login") {
                            Toggle("", isOn: $prefs.launchAtLogin)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    LinksSection(store: LinkStore.shared, expanded: $nav.linksExpanded)
                        .id("links")

                    SupportLine()
                }
                .padding(.horizontal, 32)
                .padding(.top, 48)
                .padding(.bottom, 32)
            }
            .onAppear {
                if nav.page == .links {
                    DispatchQueue.main.async { proxy.scrollTo("links", anchor: .top) }
                }
            }
            .onChange(of: nav.focusLinksRequest) {
                withAnimation(.snappy) { proxy.scrollTo("links", anchor: .top) }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Support

private struct SupportLine: View {
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text("Enjoying Linky?")
                .foregroundStyle(.tertiary)
            Link(destination: Linky.supportURL) {
                Text("Buy me a coffee ☕")
                    .underline(hovering)
            }
            .foregroundStyle(.secondary)
            .onHover { hovering = $0 }
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

// MARK: - Links

private struct LinksSection: View {
    static let collapsedCount = 5

    var store: LinkStore
    @Binding var expanded: Bool
    @State private var pendingRemoval: LinkStore.Entry?

    var body: some View {
        let all = store.all
        let missing = all.filter { store.isMissing($0) }
        let found = all.filter { !store.isMissing($0) }
        let visible = expanded ? found : Array(found.prefix(Self.collapsedCount))

        VStack(alignment: .leading, spacing: 26) {
            if !missing.isEmpty {
                SettingsSection("File not found",
                                footer: "Relink it to a new file – wherever you pasted the link, it then opens the new file.") {
                    RowList(entries: missing, isMissing: true, onRemove: { pendingRemoval = $0 })
                }
            }

            SettingsSection(found.isEmpty ? "Links" : "Links · \(found.count)") {
                if found.isEmpty {
                    Text(missing.isEmpty
                         ? "No links yet. Select a file in Finder and press \(Preferences.shared.shortcut?.display ?? "your shortcut")."
                         : "No working links.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                } else {
                    RowList(entries: visible, isMissing: false, onRemove: { pendingRemoval = $0 })
                    if found.count > Self.collapsedCount {
                        Divider().opacity(0.5)
                        Button {
                            withAnimation(.snappy) { expanded.toggle() }
                        } label: {
                            HStack(spacing: 5) {
                                Text(expanded ? "Show less" : "Show all \(found.count)")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .rotationEffect(.degrees(expanded ? 180 : 0))
                            }
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear { store.refreshStatus() }
        .alert("Remove “\(pendingRemoval?.name ?? "")”?",
               isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
               presenting: pendingRemoval) { entry in
            Button("Remove", role: .destructive) { store.remove(entry.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Wherever you pasted this link, it will stop working. The file itself stays untouched.")
        }
    }
}

private struct RowList: View {
    let entries: [LinkStore.Entry]
    let isMissing: Bool
    let onRemove: (LinkStore.Entry) -> Void

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            if index > 0 {
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)
                    .padding(.leading, 58)
            }
            LinkRow(entry: entry, isMissing: isMissing, onRemove: { onRemove(entry) })
        }
    }
}

private struct LinkRow: View {
    /// Fixed width for the trailing area, so hovering never re-truncates the text.
    static let trailingWidth: CGFloat = 124

    let entry: LinkStore.Entry
    let isMissing: Bool
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            FileIcon(path: entry.path, missing: isMissing)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isMissing ? .secondary : .primary)
                Text(isMissing ? "Last seen in \(entry.folder)" : entry.folder)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .trailing) {
                if isMissing {
                    HStack(spacing: 2) {
                        Button("Relink…") { Linky.relink(entry) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        IconButton(symbol: "trash", help: "Remove link", action: onRemove)
                    }
                } else {
                    Text(entry.used.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US"))))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .opacity(hovering ? 0 : 1)
                    HStack(spacing: 2) {
                        IconButton(symbol: "doc.on.doc", help: "Copy link") { Linky.copyAgain(entry) }
                        IconButton(symbol: "folder", help: "Show in Finder") { Linky.reveal(entry) }
                        IconButton(symbol: "arrow.triangle.2.circlepath", help: "Relink to another file…") { Linky.relink(entry) }
                        IconButton(symbol: "trash", help: "Remove link", action: onRemove)
                    }
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
                }
            }
            .frame(width: Self.trailingWidth, height: 28, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct FileIcon: View {
    let path: String
    let missing: Bool

    var body: some View {
        Group {
            if missing {
                Image(systemName: "questionmark.folder")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.orange)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .interpolation(.high)
            }
        }
        .frame(width: 30, height: 30)
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? .primary : .secondary)
        .help(help)
        .onHover { hovering = $0 }
    }
}

// MARK: - Building blocks

private struct IconTile: View {
    let symbol: String
    var size: CGFloat = 56

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(Color(white: 0.11))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

private struct HeaderCard: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            IconTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Card())
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let footer: String?
    @ViewBuilder let content: Content

    init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .padding(.leading, 2)
            VStack(spacing: 0) { content }
                .background(Card())
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
                    .padding(.top, 2)
            }
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private struct Card: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.primary.opacity(0.045))
    }
}

// MARK: - Shortcut recorder

private struct ShortcutField: View {
    @Binding var shortcut: Shortcut?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(recording || shortcut == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity)
            if shortcut != nil && !recording {
                Button { shortcut = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove shortcut")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(width: 176, height: 30)
        .background {
            Capsule(style: .circular)
                .fill(Color.primary.opacity(0.06))
                .stroke(recording ? Color.accentColor : Color.primary.opacity(0.1),
                        lineWidth: recording ? 1.5 : 1)
        }
        .contentShape(Capsule(style: .circular))
        .onTapGesture { recording ? stop() : start() }
        .onDisappear { stop() }
    }

    private var label: String {
        if recording { return "Press keys…" }
        return shortcut?.display ?? "Record shortcut"
    }

    private func start() {
        recording = true
        HotKey.shared.unregister() // so the current shortcut can be pressed again
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 53: // Esc cancels
                stop()
            case 51 where event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty: // ⌫ clears
                shortcut = nil
                stop(reapply: false)
            default:
                guard let s = Shortcut(event: event) else { NSSound.beep(); return nil }
                stop(reapply: false)
                shortcut = s
            }
            return nil
        }
    }

    private func stop(reapply: Bool = true) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording && reapply { Preferences.shared.applyShortcut() }
        recording = false
    }
}
