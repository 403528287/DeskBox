import AppKit
import SwiftUI
import QuartzCore

struct WorkspaceSwitcherView: View {
    @ObservedObject var workspaceState: WorkspaceState

    let itemCount: (UUID) -> Int
    let onSelect: (UUID) -> Void
    let onCreate: () -> Void
    let onRenameCurrent: () -> Void
    let onDeleteCurrent: () -> Void
    let onToggleLayoutLock: () -> Void
    let onSaveLayout: () -> Void
    let onRestoreLayout: () -> Void
    let onClose: () -> Void

    private let cardColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVGrid(
                    columns: cardColumns,
                    spacing: 10
                ) {
                    ForEach(
                        Array(workspaceState.workspaces.enumerated()),
                        id: \.element.id
                    ) { index, workspace in
                        workspaceCard(
                            workspace,
                            index: index
                        )
                    }

                    createCard
                }
                .padding(14)
            }

            footer
        }
        .frame(width: 390, height: 430)
        .background {
            ZStack {
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 30,
                        bottomLeading: 44,
                        bottomTrailing: 30,
                        topTrailing: 44
                    ),
                    style: .continuous
                )
                .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [
                        Color.blue.opacity(0.12),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 4,
                    endRadius: 250
                )

                RadialGradient(
                    colors: [
                        Color.purple.opacity(0.08),
                        Color.clear
                    ],
                    center: .bottomLeading,
                    startRadius: 10,
                    endRadius: 220
                )
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 30,
                    bottomLeading: 44,
                    bottomTrailing: 30,
                    topTrailing: 44
                ),
                style: .continuous
            )
        )
        .overlay {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 30,
                    bottomLeading: 44,
                    bottomTrailing: 30,
                    topTrailing: 44
                ),
                style: .continuous
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.72),
                        Color.white.opacity(0.16),
                        Color.white.opacity(0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            Capsule()
                .fill(Color.white.opacity(0.34))
                .frame(width: 116, height: 2)
                .blur(radius: 0.5)
                .padding(.leading, 34)
                .padding(.top, 10)
                .allowsHitTesting(false)
        }
        .shadow(
            color: Color.black.opacity(0.18),
            radius: 30,
            x: 0,
            y: 16
        )
        .animation(
            .snappy(duration: 0.26, extraBounce: 0.05),
            value: workspaceState.currentID
        )
    }

    private var header: some View {
        ZStack {
            WindowDragHandle(onDoubleClick: {})
                .contentShape(Rectangle())

            LinearGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.blue.opacity(0.08),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .allowsHitTesting(false)

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 14,
                        style: .continuous
                    )
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 14,
                            style: .continuous
                        )
                        .stroke(
                            Color.white.opacity(0.38),
                            lineWidth: 1
                        )
                    }
                    .frame(width: 42, height: 42)

                    Image(systemName: "rectangle.3.group.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.72))
                }
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 3) {
                    Text("工作区")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.88))

                    Text(currentWorkspaceSubtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(
                            Color.primary.opacity(0.60)
                        )
                        .lineLimit(1)
                }
                .allowsHitTesting(false)

                Spacer()

                headerButton(
                    systemName: "plus",
                    help: "新建工作区",
                    action: onCreate
                )

                headerButton(
                    systemName: "xmark",
                    help: "关闭工作区面板",
                    action: onClose
                )
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 76)
    }

    private var currentWorkspaceSubtitle: String {
        guard let current = workspaceState.workspaces.first(
            where: { $0.id == workspaceState.currentID }
        ) else {
            return "管理你的桌面场景"
        }

        let count = itemCount(current.id)
        return "当前：\(current.name) · \(count) 个项目"
    }

    private func headerButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.74))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(.thinMaterial)
                )
                .overlay {
                    Circle()
                        .stroke(
                            Color.white.opacity(0.36),
                            lineWidth: 1
                        )
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func workspaceCard(
        _ workspace: WorkspaceConfig,
        index: Int
    ) -> some View {
        let isCurrent = workspace.id == workspaceState.currentID
        let count = itemCount(workspace.id)

        return Button {
            if !isCurrent {
                onSelect(workspace.id)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .fill(.thinMaterial)

                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            iconTint(index: index)
                                .opacity(isCurrent ? 0.20 : 0.07),
                            Color.white.opacity(
                                isCurrent ? 0.12 : 0.035
                            ),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(
                                isCurrent ? 0.72 : 0.34
                            ),
                            Color.white.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isCurrent ? 1.2 : 1
                )

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ZStack {
                            RoundedRectangle(
                                cornerRadius: 9,
                                style: .continuous
                            )
                            .fill(.thinMaterial)
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: 9,
                                    style: .continuous
                                )
                                .fill(
                                    iconTint(index: index)
                                        .opacity(isCurrent ? 0.14 : 0.08)
                                )
                            }
                            .frame(width: 34, height: 34)

                            Image(
                                systemName: isCurrent
                                    ? "rectangle.3.group.fill"
                                    : "rectangle.3.group"
                            )
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                iconTint(index: index)
                            )
                        }

                        Spacer()

                        if isCurrent {
                            HStack(spacing: 4) {
                                if workspaceState.isCurrentLayoutLocked {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 8.5, weight: .bold))
                                }

                                Text("当前")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                                .foregroundStyle(
                                    Color.primary.opacity(0.72)
                                )
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(.thinMaterial)
                                )
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            Color.white.opacity(0.36),
                                            lineWidth: 1
                                        )
                                }
                        }
                    }

                    Spacer(minLength: 0)

                    Text(workspace.name)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(
                            Color.primary.opacity(0.86)
                        )
                        .lineLimit(1)

                    Text(
                        count == 0
                            ? "空工作区"
                            : "\(count) 个桌面项目"
                    )
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(
                        Color.primary.opacity(0.58)
                    )
                }
                .padding(12)
            }
            .frame(height: 116)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var createCard: some View {
        Button(action: onCreate) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }

                Text("新建工作区")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("创建新的桌面场景")
                    .font(.system(size: 10))
                    .foregroundStyle(
                        Color.primary.opacity(0.56)
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 116)
            .background(
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .fill(.thinMaterial)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .stroke(
                    Color.white.opacity(0.30),
                    style: StrokeStyle(
                        lineWidth: 1,
                        dash: [5, 4]
                    )
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                footerButton(
                    title: workspaceState.isCurrentLayoutLocked
                        ? "解锁布局"
                        : "锁定布局",
                    systemName: workspaceState.isCurrentLayoutLocked
                        ? "lock.open"
                        : "lock",
                    action: onToggleLayoutLock
                )

                footerButton(
                    title: "保存布局",
                    systemName: "square.and.arrow.down",
                    action: onSaveLayout
                )

                footerButton(
                    title: "恢复布局",
                    systemName: "arrow.counterclockwise",
                    isDisabled: !workspaceState.currentHasLayoutSnapshot,
                    action: onRestoreLayout
                )
            }

            HStack(spacing: 8) {
                footerButton(
                    title: "重命名",
                    systemName: "pencil",
                    action: onRenameCurrent
                )

                Spacer()

                footerButton(
                    title: "删除当前",
                    systemName: "trash",
                    destructive: true,
                    isDisabled: workspaceState.workspaces.count <= 1,
                    action: onDeleteCurrent
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            .ultraThinMaterial
        )
        .overlay(alignment: .top) {
            Divider()
                .opacity(0.22)
        }
    }

    private func footerButton(
        title: String,
        systemName: String,
        destructive: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(
                        cornerRadius: 11,
                        style: .continuous
                    )
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: 11,
                            style: .continuous
                        )
                        .stroke(
                            Color.white.opacity(0.28),
                            lineWidth: 1
                        )
                    }
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(destructive ? Color.red : Color.primary)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.34 : 1)
    }

    private func activeGradient(index: Int) -> AnyShapeStyle {
        let palettes: [[Color]] = [
            [
                Color(red: 0.48, green: 0.34, blue: 0.98),
                Color(red: 0.26, green: 0.58, blue: 0.98)
            ],
            [
                Color(red: 0.98, green: 0.42, blue: 0.42),
                Color(red: 0.98, green: 0.61, blue: 0.26)
            ],
            [
                Color(red: 0.14, green: 0.70, blue: 0.62),
                Color(red: 0.20, green: 0.55, blue: 0.96)
            ],
            [
                Color(red: 0.86, green: 0.34, blue: 0.78),
                Color(red: 0.50, green: 0.32, blue: 0.96)
            ]
        ]

        let colors = palettes[index % palettes.count]
        return AnyShapeStyle(
            LinearGradient(
                colors: colors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func inactiveFill(index: Int) -> AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [
                    iconTint(index: index).opacity(0.10),
                    Color.primary.opacity(0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func iconTint(index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.46, green: 0.34, blue: 0.96),
            Color(red: 0.96, green: 0.40, blue: 0.32),
            Color(red: 0.10, green: 0.66, blue: 0.58),
            Color(red: 0.86, green: 0.32, blue: 0.74),
            Color(red: 0.18, green: 0.56, blue: 0.96)
        ]
        return colors[index % colors.count]
    }
}

@MainActor
final class WorkspaceSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WorkspaceSwitcherPanelController:
    NSObject,
    NSWindowDelegate
{
    private let manager: ZoneManager
    private var panel: WorkspaceSwitcherPanel?
    private var isProgrammaticMove = false

    private let positionXKey = "DeskBox.WorkspacePanel.X.v1"
    private let positionYKey = "DeskBox.WorkspacePanel.Y.v1"

    init(manager: ZoneManager) {
        self.manager = manager
        super.init()
    }

    func toggle(relativeTo statusButton: NSStatusBarButton?) {
        if let panel, panel.isVisible {
            hide()
            return
        }

        show(relativeTo: statusButton)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func show(relativeTo statusButton: NSStatusBarButton?) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = panel ?? makePanel()
        var frame = panel.frame
        frame.size = NSSize(width: 390, height: 430)

        if let savedOrigin = savedPanelOrigin() {
            frame.origin = savedOrigin
        } else if let statusButton,
                  let buttonWindow = statusButton.window {
            let rectInWindow = statusButton.convert(
                statusButton.bounds,
                to: nil
            )
            let buttonFrame = buttonWindow.convertToScreen(rectInWindow)

            frame.origin.x = buttonFrame.midX - frame.width / 2
            frame.origin.y = buttonFrame.minY - frame.height - 10
        } else if let screen = NSScreen.main?.visibleFrame {
            frame.origin.x = screen.maxX - frame.width - 18
            frame.origin.y = screen.maxY - frame.height - 18
        }

        let targetScreen = NSScreen.screens.first(where: {
            $0.frame.contains(
                NSPoint(
                    x: frame.midX,
                    y: frame.midY
                )
            )
        })?.visibleFrame
            ?? NSScreen.main?.visibleFrame

        if let screen = targetScreen {
            frame.origin.x = min(
                max(frame.minX, screen.minX + 10),
                screen.maxX - frame.width - 10
            )
            frame.origin.y = min(
                max(frame.minY, screen.minY + 10),
                screen.maxY - frame.height - 10
            )
        }

        let finalFrame = frame
        let startFrame = frame.offsetBy(dx: 0, dy: 8)

        isProgrammaticMove = true
        panel.alphaValue = 0
        panel.setFrame(startFrame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.20, 0.78, 0.28, 1.0
            )
            panel.animator().alphaValue = 1
            panel.animator().setFrame(
                finalFrame,
                display: true
            )
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.isProgrammaticMove = false
            }
        }
    }

    private func savedPanelOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: positionXKey) != nil,
              defaults.object(forKey: positionYKey) != nil else {
            return nil
        }

        return NSPoint(
            x: defaults.double(forKey: positionXKey),
            y: defaults.double(forKey: positionYKey)
        )
    }

    private func savePanelOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set(origin.x, forKey: positionXKey)
        UserDefaults.standard.set(origin.y, forKey: positionYKey)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticMove,
              let panel else {
            return
        }

        savePanelOrigin(panel.frame.origin)
    }

    private func makePanel() -> WorkspaceSwitcherPanel {
        let rootView = WorkspaceSwitcherView(
            workspaceState: manager.workspaceState,
            itemCount: { [weak manager] id in
                manager?.workspaceItemCount(id) ?? 0
            },
            onSelect: { [weak self] id in
                self?.manager.switchWorkspace(to: id)
            },
            onCreate: { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.manager.createWorkspace()
                }
            },
            onRenameCurrent: { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.manager.renameCurrentWorkspace()
                }
            },
            onDeleteCurrent: { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.manager.deleteCurrentWorkspace()
                }
            },
            onToggleLayoutLock: { [weak self] in
                self?.manager.toggleCurrentWorkspaceLayoutLock()
            },
            onSaveLayout: { [weak self] in
                self?.manager.saveCurrentWorkspaceLayoutSnapshot()
            },
            onRestoreLayout: { [weak self] in
                self?.manager.restoreCurrentWorkspaceLayoutSnapshot()
            },
            onClose: { [weak self] in
                self?.hide()
            }
        )

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: 390,
            height: 430
        )

        let panel = WorkspaceSwitcherPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 390,
                height: 430
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]

        self.panel = panel
        return panel
    }
}
