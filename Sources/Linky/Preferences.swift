import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    @ObservationIgnored var onShortcutChange: (() -> Void)?
    @ObservationIgnored private let defaults = UserDefaults.standard

    var shortcut: Shortcut? {
        didSet {
            if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
                defaults.set(data, forKey: "shortcut")
                defaults.set(false, forKey: "shortcutCleared")
            } else {
                defaults.removeObject(forKey: "shortcut")
                defaults.set(true, forKey: "shortcutCleared")
            }
            applyShortcut()
            onShortcutChange?()
        }
    }

    var format: LinkFormat {
        didSet { defaults.set(format.rawValue, forKey: "format") }
    }

    var clickAction: ClickAction {
        didSet { defaults.set(clickAction.rawValue, forKey: "clickAction") }
    }

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                Toast.show("Couldn’t change login item", detail: error.localizedDescription,
                           symbol: "exclamationmark.triangle", style: .warning)
            }
        }
    }

    private init() {
        if let data = defaults.data(forKey: "shortcut"), let s = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = s
        } else {
            shortcut = defaults.bool(forKey: "shortcutCleared") ? nil : .default
        }
        format = LinkFormat(rawValue: defaults.string(forKey: "format") ?? "") ?? .rich
        clickAction = ClickAction(rawValue: defaults.string(forKey: "clickAction") ?? "") ?? .open
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func applyShortcut() {
        if let shortcut {
            if !HotKey.shared.register(shortcut) {
                Toast.show("Shortcut is already in use", detail: shortcut.display,
                           symbol: "keyboard", style: .warning)
            }
        } else {
            HotKey.shared.unregister()
        }
    }
}
