import SwiftUI
import AppKit

private struct DeskBoxHeaderHoverModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(
                        Color.white.opacity(
                            isHovered ? 0.15 : 0
                        )
                    )
            )
            .scaleEffect(isHovered ? 1.03 : 1)
            .animation(
                .easeOut(duration: 0.12),
                value: isHovered
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    func deskBoxHeaderHover() -> some View {
        modifier(DeskBoxHeaderHoverModifier())
    }
}

struct WindowDragHandle: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onDoubleClick = onDoubleClick
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
    }

    final class DragView: NSView {
        var onDoubleClick: (() -> Void)?

        override var mouseDownCanMoveWindow: Bool {
            if let panel = window as? DeskBoxPanel {
                return !panel.layoutLocked
            }
            return true
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            if let panel = window as? DeskBoxPanel,
               panel.layoutLocked {
                return
            }

            if event.clickCount >= 2 {
                onDoubleClick?()
                return
            }

            NSCursor.closedHand.push()
            defer { NSCursor.pop() }
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
