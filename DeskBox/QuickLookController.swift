import AppKit
import QuickLookUI

@MainActor
final class QuickLookPanel: NSPanel {
    var onSpace: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 {
            onSpace?()
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class QuickLookController {
    static let shared = QuickLookController()

    private var panel: QuickLookPanel?
    private var currentURL: URL?

    func toggle(_ url: URL) {
        if let panel, panel.isVisible, currentURL == url {
            hide()
            return
        }

        show(url)
    }

    func show(_ url: URL) {
        hide()

        guard let previewView = QLPreviewView(
            frame: NSRect(x: 0, y: 0, width: 760, height: 560),
            style: .normal
        ) else {
            return
        }

        previewView.previewItem = url as NSURL

        let panel = QuickLookPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = url.lastPathComponent
        panel.contentView = previewView
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.onSpace = { [weak self] in
            self?.hide()
        }
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        self.currentURL = url
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        currentURL = nil
    }
}
