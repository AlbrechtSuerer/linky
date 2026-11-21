import AppKit
import SwiftUI

/// A small glass capsule at the top of the screen that confirms what just happened.
@MainActor
enum Toast {
    enum Style { case success, warning }

    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ title: String, detail: String? = nil, symbol: String = "link", style: Style = .success) {
        let host = NSHostingView(rootView: ToastView(title: title, detail: detail, symbol: symbol, style: style))
        let size = host.fittingSize

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = host

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 6)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)

        hideWork?.cancel()
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    if panel.alphaValue == 0 { panel.orderOut(nil) }
                }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (style == .warning ? 2.6 : 1.6), execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

struct ToastView: View {
    let title: String
    let detail: String?
    let symbol: String
    let style: Toast.Style

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(style == .warning ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: 340, alignment: .leading)
        }
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .padding(.vertical, detail == nil ? 11 : 9)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .fixedSize()
        .padding(18) // room for the shadow
    }
}
