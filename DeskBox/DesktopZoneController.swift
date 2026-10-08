import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class DeskBoxPanel: NSPanel {
    var onBackgroundMouseDown: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           let contentView {
            let point = contentView.convert(
                event.locationInWindow,
                from: nil
            )
            let hitView = contentView.hitTest(point)

            if !isFileInteractionView(hitView) {
                onBackgroundMouseDown?()
            }
        }

        super.sendEvent(event)
    }

    private func isFileInteractionView(_ view: NSView?) -> Bool {
        var current = view

        while let candidate = current {
            if candidate is NativeFileDragSource.DragSourceView {
                return true
            }
            if candidate === contentView {
                break
            }
            current = candidate.superview
        }

        return false
    }
}

@MainActor
final class TopPinnedContentView: NSView {
    private let hostedView: NSView
    private let roundedMaskLayer = CAShapeLayer()
    private let expandedCornerRadius: CGFloat = 18

    var contentHeight: CGFloat {
        didSet {
            if abs(oldValue - contentHeight) > 0.5 {
                needsLayout = true
            }
        }
    }

    init(hostedView: NSView, contentHeight: CGFloat) {
        self.hostedView = hostedView
        self.contentHeight = contentHeight
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = expandedCornerRadius
        layer?.cornerCurve = .continuous

        // 用随 bounds 实时更新的圆角 mask 做第二层保险。
        // 折叠窗口横向缩放时，AppKit 会频繁重布局，
        // 单靠 cornerRadius 偶尔会露出矩形裁切边界。
        layer?.mask = roundedMaskLayer

        autoresizesSubviews = false
        addSubview(hostedView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()

        // SwiftUI 始终按完整展开高度布局。
        // 窗口折叠/展开时只改变这里的裁切范围，不反复重排文件网格。
        hostedView.frame = NSRect(
            x: 0,
            y: bounds.height - contentHeight,
            width: bounds.width,
            height: contentHeight
        )

        // 展开时保持原来的 18px 圆角；折叠成标题条时，
        // 圆角取高度的一半，形成真正的胶囊形。
        let radius: CGFloat
        if bounds.height <= 60 {
            radius = bounds.height / 2
        } else {
            radius = expandedCornerRadius
        }

        layer?.cornerRadius = radius

        // 每次尺寸变化都重新生成 mask，确保横向缩放后
        // 四个角严格跟随当前窗口尺寸。
        roundedMaskLayer.frame = bounds
        roundedMaskLayer.path = CGPath(
            roundedRect: bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
    }
}

@MainActor
final class DesktopZoneController: NSObject, NSWindowDelegate {
    static let collapsedHeight: CGFloat = 46

    let zoneID: UUID
    let store: ZoneStore

    private weak var manager: ZoneManager?
    private var panel: DeskBoxPanel?
    private var contentContainer: TopPinnedContentView?
    private var isAnimatingCollapse = false

    init(config: ZoneConfig, directoryURL: URL, manager: ZoneManager) {
        self.zoneID = config.id
        self.store = ZoneStore(
            zoneID: config.id,
            name: config.name,
            collapsed: config.collapsed,
            directoryURL: directoryURL
        )
        self.manager = manager
        super.init()
    }

    func show() {
        guard let manager,
              let config = manager.config(for: zoneID) else { return }

        let expandedFrame = NSRect(
            x: config.x,
            y: config.y,
            width: config.width,
            height: config.height
        )

        let initialFrame: NSRect
        if config.collapsed {
            initialFrame = NSRect(
                x: expandedFrame.minX,
                y: expandedFrame.maxY - Self.collapsedHeight,
                width: expandedFrame.width,
                height: Self.collapsedHeight
            )
        } else {
            initialFrame = expandedFrame
        }

        let panel = DeskBoxPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.onBackgroundMouseDown = { [weak manager] in
            manager?.selectionState.clear()
        }
        panel.minSize = NSSize(
            width: 280,
            height: config.collapsed ? Self.collapsedHeight : 150
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // 真正贴在桌面：高于 Finder 桌面图标，但低于所有普通应用窗口。
        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        panel.level = NSWindow.Level(rawValue: desktopIconLevel + 1)

        let rootView = ZoneView(
            store: store,
            selection: manager.selectionState,
            workspaceState: manager.workspaceState,
            onCollapse: { [weak self] collapsed in
                self?.setCollapsed(collapsed)
            },
            onNewZone: { [weak self] in
                self?.manager?.createZone()
            },
            onNewNote: { [weak self] in
                self?.manager?.createNote()
            },
            onNewChecklist: { [weak self] in
                self?.manager?.createChecklist()
            },
            onNewLauncher: { [weak self] in
                self?.manager?.createLauncher()
            },
            onRename: { [weak self] in
                guard let self else { return }
                self.manager?.promptRename(self.zoneID)
            },
            onMoveToWorkspace: { [weak self] workspaceID in
                guard let self else { return }
                self.manager?.moveZone(
                    self.zoneID,
                    toWorkspaceID: workspaceID
                )
            },
            onDelete: { [weak self] in
                guard let self else { return }
                self.manager?.deleteZone(self.zoneID)
            },
            onDropURLs: { [weak self] urls in
                guard let self else { return }
                self.manager?.moveFiles(urls, to: self.zoneID)
            }
        )

        let hostingView = NSHostingView(rootView: rootView)
        let contentContainer = TopPinnedContentView(
            hostedView: hostingView,
            contentHeight: max(expandedFrame.height, 150)
        )
        panel.contentView = contentContainer
        panel.orderFront(nil)

        self.contentContainer = contentContainer
        self.panel = panel
    }

    func rename(to newName: String, directoryURL: URL) {
        store.rename(to: newName, directoryURL: directoryURL)
    }

    func showWindow() {
        panel?.orderFront(nil)
    }

    func hideWindow() {
        panel?.orderOut(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        contentContainer = nil
    }

    private func setCollapsed(_ collapsed: Bool) {
        guard let panel,
              let config = manager?.config(for: zoneID),
              !isAnimatingCollapse,
              collapsed != store.visualCollapsed else {
            return
        }

        isAnimatingCollapse = true
        store.visualCollapsed = collapsed

        if collapsed {
            let current = panel.frame
            let top = current.maxY

            // 固定 SwiftUI 的完整展开高度；窗口动画只负责裁切。
            contentContainer?.contentHeight = current.height

            manager?.updateFrame(
                current,
                for: zoneID,
                collapsed: false
            )

            withAnimation(.easeOut(duration: 0.09)) {
                store.contentOpacity = 0
                store.contentOffset = -3
            }

            let targetFrame = NSRect(
                x: current.minX,
                y: top - Self.collapsedHeight,
                width: current.width,
                height: Self.collapsedHeight
            )

            panel.minSize = NSSize(
                width: 280,
                height: Self.collapsedHeight
            )

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.25, 0.82, 0.25, 1.0
                )
                panel.animator().setFrame(
                    targetFrame,
                    display: true
                )
            } completionHandler: { [weak self, weak panel] in
                Task { @MainActor in
                    guard let self, let panel else { return }

                    self.store.collapsed = true
                    self.manager?.setCollapsed(true, for: self.zoneID)
                    self.manager?.updateFrame(
                        panel.frame,
                        for: self.zoneID,
                        collapsed: true
                    )
                    self.isAnimatingCollapse = false
                }
            }
        } else {
            let current = panel.frame
            let expandedHeight = max(config.height, 150)
            contentContainer?.contentHeight = expandedHeight

            let targetFrame = NSRect(
                x: current.minX,
                y: current.maxY - expandedHeight,
                width: current.width,
                height: expandedHeight
            )

            // 内容一直存在，不再重建。展开时只做轻微淡入。
            store.contentOpacity = 0
            store.contentOffset = -3

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.25, 0.82, 0.25, 1.0
                )
                panel.animator().setFrame(
                    targetFrame,
                    display: true
                )
            } completionHandler: { [weak self, weak panel] in
                Task { @MainActor in
                    guard let self, let panel else { return }

                    self.store.collapsed = false
                    self.manager?.setCollapsed(false, for: self.zoneID)
                    panel.minSize = NSSize(width: 280, height: 150)
                    self.manager?.updateFrame(
                        panel.frame,
                        for: self.zoneID,
                        collapsed: false
                    )
                    self.isAnimatingCollapse = false
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
                guard let self, !self.store.visualCollapsed else { return }
                withAnimation(.easeOut(duration: 0.14)) {
                    self.store.contentOpacity = 1
                    self.store.contentOffset = 0
                }
            }
        }
    }

    func windowWillResize(
        _ sender: NSWindow,
        to frameSize: NSSize
    ) -> NSSize {
        guard store.visualCollapsed,
              !isAnimatingCollapse else {
            return frameSize
        }

        return NSSize(
            width: max(frameSize.width, 280),
            height: Self.collapsedHeight
        )
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel, !isAnimatingCollapse else { return }
        manager?.updateFrame(
            panel.frame,
            for: zoneID,
            collapsed: store.collapsed
        )
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel, !isAnimatingCollapse else { return }

        if !store.collapsed {
            contentContainer?.contentHeight = panel.frame.height
        }

        manager?.updateFrame(
            panel.frame,
            for: zoneID,
            collapsed: store.collapsed
        )
    }
}
