import SwiftUI
import AppKit

struct NativeFileDragSource: NSViewRepresentable {
    let url: URL
    let isSelected: Bool
    let onClick: (Bool, Bool) -> Void
    let onContextClick: () -> Void
    let dragURLs: () -> [URL]
    let contextURLs: () -> [URL]
    let onDoubleClick: () -> Void
    let onPreview: () -> Void
    let onOpenURLs: ([URL]) -> Void
    let onRevealURLs: ([URL]) -> Void
    let onMoveToDesktopURLs: ([URL]) -> Void
    let onDropURLs: ([URL], Bool) -> Bool
    let onHoverURLs: ([URL], Bool) -> Void
    let onTargeted: (Bool, Bool) -> Void
    let onDragEnded: (Bool) -> Void

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        configure(view)
        view.registerForDraggedTypes([.fileURL])
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: DragSourceView) {
        view.url = url
        view.isSelected = isSelected
        view.onClick = onClick
        view.onContextClick = onContextClick
        view.dragURLs = dragURLs
        view.contextURLs = contextURLs
        view.onDoubleClick = onDoubleClick
        view.onPreview = onPreview
        view.onOpenURLs = onOpenURLs
        view.onRevealURLs = onRevealURLs
        view.onMoveToDesktopURLs = onMoveToDesktopURLs
        view.onDropURLs = onDropURLs
        view.onHoverURLs = onHoverURLs
        view.onTargeted = onTargeted
        view.onDragEnded = onDragEnded
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var url: URL?
        var isSelected = false
        var onClick: ((Bool, Bool) -> Void)?
        var onContextClick: (() -> Void)?
        var dragURLs: (() -> [URL])?
        var contextURLs: (() -> [URL])?
        var onDoubleClick: (() -> Void)?
        var onPreview: (() -> Void)?
        var onOpenURLs: (([URL]) -> Void)?
        var onRevealURLs: (([URL]) -> Void)?
        var onMoveToDesktopURLs: (([URL]) -> Void)?
        var onDropURLs: (([URL], Bool) -> Bool)?
        var onHoverURLs: (([URL], Bool) -> Void)?
        var onTargeted: ((Bool, Bool) -> Void)?
        var onDragEnded: ((Bool) -> Void)?

        private var mouseDownPoint: NSPoint?
        private var mouseDownUsedCommand = false
        private var mouseDownUsedShift = false
        private var didStartDrag = false
        private var shouldCollapseSelectionOnMouseUp = false

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            mouseDownPoint = convert(event.locationInWindow, from: nil)
            mouseDownUsedCommand = event.modifierFlags.contains(.command)
            mouseDownUsedShift = event.modifierFlags.contains(.shift)
            didStartDrag = false
            shouldCollapseSelectionOnMouseUp = false

            if event.clickCount >= 2 {
                onDoubleClick?()
                return
            }

            if mouseDownUsedCommand || mouseDownUsedShift {
                onClick?(mouseDownUsedCommand, mouseDownUsedShift)
            } else if isSelected {
                // 已经属于当前多选集合：先保留整组，方便直接拖动。
                // 如果最终只是普通点击而没有拖动，再在 mouseUp 收回成单选。
                shouldCollapseSelectionOnMouseUp = true
            } else {
                // 未选中的项目被普通点击时，立即切成单选；
                // 这样从未选中项目开始拖动时只拖它自己。
                onClick?(false, false)
            }
        }

        override func mouseUp(with event: NSEvent) {
            if !didStartDrag,
               !mouseDownUsedCommand,
               !mouseDownUsedShift,
               shouldCollapseSelectionOnMouseUp {
                onClick?(false, false)
            }

            mouseDownPoint = nil
            shouldCollapseSelectionOnMouseUp = false
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 49 {
                onPreview?()
                return
            }
            super.keyDown(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let url else { return }

            let current = convert(event.locationInWindow, from: nil)
            if let start = mouseDownPoint {
                let dx = current.x - start.x
                let dy = current.y - start.y
                if hypot(dx, dy) < 5 {
                    return
                }
            }

            didStartDrag = true

            let urls = dragURLs?() ?? [url]
            guard !urls.isEmpty else { return }

            let origin = mouseDownPoint ?? NSPoint(
                x: bounds.midX,
                y: bounds.midY
            )

            let draggingItems = urls.enumerated().map { index, itemURL in
                let item = NSDraggingItem(
                    pasteboardWriter: itemURL as NSURL
                )

                let sourceIcon = NSWorkspace.shared.icon(
                    forFile: itemURL.path
                )
                let dragImage = (sourceIcon.copy() as? NSImage)
                    ?? sourceIcon
                dragImage.size = NSSize(width: 48, height: 48)

                let offset = CGFloat(min(index, 6)) * 2
                item.setDraggingFrame(
                    NSRect(
                        x: origin.x - 24 + offset,
                        y: origin.y - 24 - offset,
                        width: 48,
                        height: 48
                    ),
                    contents: dragImage
                )
                return item
            }

            let session = beginDraggingSession(
                with: draggingItems,
                event: event,
                source: self
            )
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .move
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
            true
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            onDragEnded?(!operation.isEmpty)
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            let urls = draggedFileURLs(from: sender)
            guard !urls.isEmpty else { return [] }

            if isDraggingCurrentItem(urls) {
                onTargeted?(false, false)
                return .move
            }

            let after = isAfterTarget(sender)
            onTargeted?(true, after)
            onHoverURLs?(urls, after)
            return .move
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            let urls = draggedFileURLs(from: sender)
            guard !urls.isEmpty else { return [] }

            if isDraggingCurrentItem(urls) {
                onTargeted?(false, false)
                return .move
            }

            let after = isAfterTarget(sender)
            onTargeted?(true, after)
            onHoverURLs?(urls, after)
            return .move
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            onTargeted?(false, false)
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let urls = draggedFileURLs(from: sender)
            guard !urls.isEmpty else { return false }

            if isDraggingCurrentItem(urls) {
                onTargeted?(false, false)
                return true
            }

            let after = isAfterTarget(sender)
            onTargeted?(false, after)
            return onDropURLs?(urls, after) ?? false
        }

        override func concludeDragOperation(_ sender: NSDraggingInfo?) {
            onTargeted?(false, false)
        }

        private func isAfterTarget(_ sender: NSDraggingInfo) -> Bool {
            let point = convert(sender.draggingLocation, from: nil)
            return point.x >= bounds.midX
        }

        private func isDraggingCurrentItem(_ urls: [URL]) -> Bool {
            guard let url else { return false }

            let targetPath = url.standardizedFileURL.path
            return urls.contains {
                $0.standardizedFileURL.path == targetPath
            }
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            onContextClick?()
            let urls = currentContextURLs()
            let count = max(urls.count, 1)
            let menu = NSMenu()

            let open = NSMenuItem(
                title: count > 1 ? "打开所选 \(count) 项" : "打开",
                action: #selector(openItems),
                keyEquivalent: ""
            )
            open.target = self
            menu.addItem(open)

            if count == 1 {
                let preview = NSMenuItem(
                    title: "快速查看",
                    action: #selector(previewItem),
                    keyEquivalent: ""
                )
                preview.target = self
                menu.addItem(preview)
            }

            let reveal = NSMenuItem(
                title: count > 1
                    ? "在 Finder 中显示所选 \(count) 项"
                    : "在 Finder 中显示",
                action: #selector(revealItems),
                keyEquivalent: ""
            )
            reveal.target = self
            menu.addItem(reveal)

            menu.addItem(.separator())

            let moveBack = NSMenuItem(
                title: count > 1
                    ? "将所选 \(count) 项移回桌面"
                    : "移回桌面",
                action: #selector(moveBackItems),
                keyEquivalent: ""
            )
            moveBack.target = self
            menu.addItem(moveBack)

            return menu
        }

        @objc private func openItems() {
            onOpenURLs?(currentContextURLs())
        }

        @objc private func previewItem() {
            onPreview?()
        }

        @objc private func revealItems() {
            onRevealURLs?(currentContextURLs())
        }

        @objc private func moveBackItems() {
            onMoveToDesktopURLs?(currentContextURLs())
        }

        private func currentContextURLs() -> [URL] {
            if let urls = contextURLs?(), !urls.isEmpty {
                return urls
            }
            if let url {
                return [url]
            }
            return []
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .arrow)
        }

        private func draggedFileURLs(from sender: NSDraggingInfo) -> [URL] {
            let objects = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) ?? []

            return objects.compactMap { object in
                guard let nsURL = object as? NSURL else { return nil }
                return nsURL as URL
            }
        }
    }
}
