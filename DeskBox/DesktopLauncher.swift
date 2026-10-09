import AppKit
import Combine
import SwiftUI
import QuartzCore
import UniformTypeIdentifiers

struct LauncherItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case website
        case file
    }

    let id: UUID
    var title: String
    var target: String
    var kind: Kind
}

struct LauncherConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var items: [LauncherItem]
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var themeRawValue: String?
    var collapsed: Bool?
    var isPinned: Bool?

    var theme: NoteTheme {
        get {
            guard let themeRawValue,
                  let theme = NoteTheme(rawValue: themeRawValue) else {
                return .blue
            }
            return theme
        }
        set {
            themeRawValue = newValue.rawValue
        }
    }

    var collapsedValue: Bool {
        get { collapsed ?? false }
        set { collapsed = newValue }
    }

    var pinnedValue: Bool {
        get { isPinned ?? false }
        set { isPinned = newValue }
    }
}

@MainActor
final class LauncherStore: ObservableObject {
    let id: UUID

    @Published var title: String
    @Published var items: [LauncherItem]
    @Published var theme: NoteTheme
    @Published var visualCollapsed: Bool
    @Published var isPinned: Bool
    @Published var contentOpacity: Double
    @Published var contentOffset: CGFloat

    init(config: LauncherConfig) {
        id = config.id
        title = config.title
        items = config.items
        theme = config.theme
        visualCollapsed = config.collapsedValue
        isPinned = config.pinnedValue
        contentOpacity = config.collapsedValue ? 0 : 1
        contentOffset = config.collapsedValue ? -3 : 0
    }

    func addWebsite(title: String, urlString: String) {
        var value = urlString.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !value.isEmpty else { return }

        if !value.contains("://") {
            value = "https://" + value
        }

        guard URL(string: value) != nil else { return }

        let trimmedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        items.append(
            LauncherItem(
                id: UUID(),
                title: trimmedTitle.isEmpty ? value : trimmedTitle,
                target: value,
                kind: .website
            )
        )
    }

    func addFileURL(_ url: URL) {
        let standardized = url.standardizedFileURL
        items.append(
            LauncherItem(
                id: UUID(),
                title: standardized.deletingPathExtension().lastPathComponent,
                target: standardized.path,
                kind: .file
            )
        )
    }

    func remove(_ id: UUID) {
        items.removeAll(where: { $0.id == id })
    }

    func isUnavailable(_ item: LauncherItem) -> Bool {
        switch item.kind {
        case .website:
            return false
        case .file:
            return !FileManager.default.fileExists(
                atPath: item.target
            )
        }
    }

    func open(_ item: LauncherItem) {
        switch item.kind {
        case .website:
            guard let url = URL(string: item.target) else { return }
            NSWorkspace.shared.open(url)

        case .file:
            let url = URL(fileURLWithPath: item.target)
            guard FileManager.default.fileExists(atPath: url.path) else {
                NSSound.beep()
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    func icon(for item: LauncherItem) -> NSImage {
        switch item.kind {
        case .website:
            return NSImage(
                systemSymbolName: "globe",
                accessibilityDescription: nil
            ) ?? NSImage()

        case .file:
            if FileManager.default.fileExists(atPath: item.target) {
                return NSWorkspace.shared.icon(forFile: item.target)
            }
            return NSImage(
                systemSymbolName: "questionmark.square.dashed",
                accessibilityDescription: nil
            ) ?? NSImage()
        }
    }
}

struct LauncherView: View {
    @ObservedObject var store: LauncherStore
    @ObservedObject var workspaceState: WorkspaceState
    @State private var hoveredItemID: UUID?

    let onUpdate: (String, [LauncherItem], NoteTheme) -> Void
    let onCollapse: (Bool) -> Void
    let onTogglePin: () -> Void
    let onMoveToWorkspace: (UUID) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 0) {
                Divider()
                    .opacity(0.18)

                ZStack {
                    store.theme.bodyGradient

                    if store.items.isEmpty {
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.34))
                                    .frame(width: 44, height: 44)

                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Color.black.opacity(0.34))
                            }

                            Text("还没有快捷入口")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.58))

                            Text("点击右上角 + 添加网站、文件夹或应用")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Color.black.opacity(0.38))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: [
                                    GridItem(.adaptive(minimum: 82), spacing: 10)
                                ],
                                spacing: 12
                            ) {
                                ForEach(store.items) { item in
                                    launcherTile(item)
                                }
                            }
                            .padding(12)
                        }
                    }
                }
            }
            .opacity(store.contentOpacity)
            .offset(y: store.contentOffset)
        }
        .animation(
            .easeInOut(duration: 0.18),
            value: store.theme
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
            .stroke(store.theme.borderColor, lineWidth: 1)
            .allowsHitTesting(false)
        }
    }

    private var header: some View {
        ZStack {
            store.theme.headerGradient

            WindowDragHandle {
                onCollapse(!store.visualCollapsed)
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(store.theme.headerForeground)

                TextField("快捷入口", text: $store.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(store.theme.headerForeground)
                    .lineLimit(1)
                    .frame(maxWidth: 145, alignment: .leading)
                    .onChange(of: store.title) { _, _ in
                        persist()
                    }

                if workspaceState.isCurrentLayoutLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(
                            store.theme.headerForeground.opacity(0.72)
                        )
                        .help("当前工作区布局已锁定")
                }

                Spacer(minLength: 8)

                Menu {
                    Button("添加网站…") {
                        // Menu 仍在 tracking 时直接 runModal 可能被系统吞掉。
                        // 等菜单关闭一帧后再弹网站输入框。
                        DispatchQueue.main.async {
                            addWebsite()
                        }
                    }
                    Button("添加文件或文件夹…") {
                        addFileOrFolder()
                    }
                    Button("添加应用程序…") {
                        addApplication()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(store.theme.headerForeground)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                        .deskBoxHeaderHover()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("添加快捷入口")

                Button(action: onTogglePin) {
                    Image(
                        systemName: store.isPinned
                            ? "pin.fill"
                            : "pin"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.theme.headerForeground)
                    .rotationEffect(.degrees(store.isPinned ? 0 : -20))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
                    .deskBoxHeaderHover()
                }
                .buttonStyle(.plain)
                .help(store.isPinned ? "取消置顶" : "置顶快捷入口")

                Menu {
                    Section("外观颜色") {
                        ForEach(NoteTheme.allCases, id: \.rawValue) { theme in
                            Button {
                                store.theme = theme
                                persist()
                            } label: {
                                Label(
                                    theme.title,
                                    systemImage: store.theme == theme
                                        ? "checkmark.circle.fill"
                                        : "circle.fill"
                                )
                            }
                        }
                    }

                    Divider()

                    Button(
                        store.isPinned ? "取消置顶" : "置顶快捷入口",
                        action: onTogglePin
                    )

                    Button(
                        store.visualCollapsed ? "展开快捷入口" : "折叠快捷入口"
                    ) {
                        onCollapse(!store.visualCollapsed)
                    }
                    .disabled(workspaceState.isCurrentLayoutLocked)

                    if workspaceState.workspaces.count > 1 {
                        Menu("移动到工作区") {
                            ForEach(
                                workspaceState.workspaces.filter {
                                    $0.id != workspaceState.currentID
                                }
                            ) { workspace in
                                Button(workspace.name) {
                                    onMoveToWorkspace(workspace.id)
                                }
                            }
                        }
                    }

                    Divider()

                    Button("删除快捷入口", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(store.theme.headerForeground)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                        .deskBoxHeaderHover()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("快捷入口设置")

                Button {
                    onCollapse(!store.visualCollapsed)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(store.theme.headerForeground)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                        .deskBoxHeaderHover()
                        .rotationEffect(
                            .degrees(store.visualCollapsed ? 180 : 0)
                        )
                        .animation(
                            .easeInOut(duration: 0.20),
                            value: store.visualCollapsed
                        )
                }
                .buttonStyle(.plain)
                .disabled(workspaceState.isCurrentLayoutLocked)
                .opacity(workspaceState.isCurrentLayoutLocked ? 0.42 : 1)
                .help(
                    workspaceState.isCurrentLayoutLocked
                        ? "布局已锁定"
                        : (store.visualCollapsed ? "展开" : "折叠")
                )
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 42)
        .clipShape(
            RoundedRectangle(
                cornerRadius: store.visualCollapsed ? 21 : 0,
                style: .continuous
            )
        )
    }

    private func launcherTile(_ item: LauncherItem) -> some View {
        let unavailable = store.isUnavailable(item)

        return Button {
            store.open(item)
        } label: {
            VStack(spacing: 6) {
                Image(nsImage: store.icon(for: item))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)

                Text(item.title)
                    .font(.system(size: 11))
                    .foregroundStyle(
                        Color.black.opacity(
                            unavailable ? 0.46 : 0.78
                        )
                    )
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)

                if unavailable {
                    Text("已失效")
                        .font(
                            .system(
                                size: 9,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(
                            Color.orange.opacity(0.82)
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(
                    cornerRadius: 11,
                    style: .continuous
                )
                .fill(
                    Color.white.opacity(
                        hoveredItemID == item.id ? 0.52 : 0.36
                    )
                )
            )
            .scaleEffect(hoveredItemID == item.id ? 1.015 : 1)
            .animation(
                .easeOut(duration: 0.12),
                value: hoveredItemID
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredItemID = item.id
            } else if hoveredItemID == item.id {
                hoveredItemID = nil
            }
        }
        .contextMenu {
            Button("打开") {
                store.open(item)
            }
            .disabled(unavailable)

            Divider()

            Button("移除快捷入口", role: .destructive) {
                store.remove(item.id)
                persist()
            }
        }
        .help(
            unavailable
                ? "原文件、文件夹或应用已不存在：\(item.target)"
                : item.target
        )
    }

    private func addWebsite() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "添加网站"
        alert.informativeText = "输入名称和网址"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")

        let container = NSView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 62)
        )

        let titleField = NSTextField(
            frame: NSRect(x: 0, y: 34, width: 320, height: 24)
        )
        titleField.placeholderString = "名称，例如：项目后台"

        let urlField = NSTextField(
            frame: NSRect(x: 0, y: 2, width: 320, height: 24)
        )
        urlField.placeholderString = "网址，例如：www.example.com"

        container.addSubview(titleField)
        container.addSubview(urlField)
        alert.accessoryView = container

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let before = store.items.count
        store.addWebsite(
            title: titleField.stringValue,
            urlString: urlField.stringValue
        )

        if store.items.count == before {
            NSSound.beep()
            return
        }

        persist()
    }

    private func addFileOrFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择文件或文件夹"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            store.addFileURL(url)
        }
        persist()
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择应用程序"
        panel.prompt = "添加"
        panel.directoryURL = URL(
            fileURLWithPath: "/Applications",
            isDirectory: true
        )
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            store.addFileURL(url)
        }
        persist()
    }

    private func persist() {
        onUpdate(
            store.title,
            store.items,
            store.theme
        )
    }
}

@MainActor
final class DesktopLauncherController: NSObject, NSWindowDelegate {
    static let collapsedHeight: CGFloat = 42

    let launcherID: UUID
    let store: LauncherStore

    private weak var manager: ZoneManager?
    private var panel: DeskBoxPanel?
    private var contentContainer: TopPinnedContentView?
    private var isAnimatingCollapse = false

    init(config: LauncherConfig, manager: ZoneManager) {
        launcherID = config.id
        store = LauncherStore(config: config)
        self.manager = manager
        super.init()
    }

    func show() {
        guard panel == nil,
              let manager,
              let config = manager.launcherConfig(for: launcherID) else {
            return
        }

        let expandedFrame = NSRect(
            x: config.x,
            y: config.y,
            width: max(config.width, 260),
            height: max(config.height, 210)
        )

        let initialFrame: NSRect
        if config.collapsedValue {
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
            width: 260,
            height: config.collapsedValue
                ? Self.collapsedHeight
                : 210
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle
        ]

        self.panel = panel
        applyWindowLevel()

        let rootView = LauncherView(
            store: store,
            workspaceState: manager.workspaceState,
            onUpdate: { [weak manager, launcherID] title, items, theme in
                manager?.updateLauncher(
                    launcherID,
                    title: title,
                    items: items,
                    theme: theme
                )
            },
            onCollapse: { [weak self] collapsed in
                self?.setCollapsed(collapsed)
            },
            onTogglePin: { [weak self] in
                self?.togglePin()
            },
            onMoveToWorkspace: { [weak manager, launcherID] workspaceID in
                manager?.moveLauncher(
                    launcherID,
                    toWorkspaceID: workspaceID
                )
            },
            onDelete: { [weak manager, launcherID] in
                manager?.deleteLauncher(launcherID)
            }
        )

        let hostingView = NSHostingView(rootView: rootView)
        let contentContainer = TopPinnedContentView(
            hostedView: hostingView,
            contentHeight: expandedFrame.height
        )

        panel.contentView = contentContainer
        panel.orderFront(nil)
        self.contentContainer = contentContainer
    }

    func showWindow() {
        if panel == nil {
            show()
        } else {
            panel?.orderFront(nil)
        }
    }

    func hideWindow() {
        panel?.orderOut(nil)
    }

    func setLayoutLocked(_ locked: Bool) {
        guard let panel else { return }
        panel.layoutLocked = locked

        if locked {
            panel.styleMask.remove(.resizable)
        } else {
            panel.styleMask.insert(.resizable)
        }
    }

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        contentContainer = nil
    }

    private func togglePin() {
        store.isPinned.toggle()
        manager?.setLauncherPinned(
            store.isPinned,
            for: launcherID
        )
        applyWindowLevel()
        panel?.orderFront(nil)
    }

    private func applyWindowLevel() {
        guard let panel else { return }

        let desktopIconLevel = Int(
            CGWindowLevelForKey(.desktopIconWindow)
        )
        panel.level = NSWindow.Level(
            rawValue: desktopIconLevel + (store.isPinned ? 2 : 1)
        )
    }

    private func setCollapsed(_ collapsed: Bool) {
        guard manager?.isCurrentWorkspaceLayoutLocked != true,
              let panel,
              let config = manager?.launcherConfig(for: launcherID),
              !isAnimatingCollapse,
              collapsed != store.visualCollapsed else {
            return
        }

        isAnimatingCollapse = true
        store.visualCollapsed = collapsed

        if collapsed {
            let current = panel.frame
            let top = current.maxY

            contentContainer?.contentHeight = current.height
            manager?.updateLauncherFrame(
                current,
                for: launcherID,
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
                width: 260,
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

                    self.manager?.setLauncherCollapsed(
                        true,
                        for: self.launcherID
                    )
                    self.manager?.updateLauncherFrame(
                        panel.frame,
                        for: self.launcherID,
                        collapsed: true
                    )
                    self.isAnimatingCollapse = false
                }
            }
        } else {
            let current = panel.frame
            let expandedHeight = max(config.height, 210)
            contentContainer?.contentHeight = expandedHeight

            let targetFrame = NSRect(
                x: current.minX,
                y: current.maxY - expandedHeight,
                width: current.width,
                height: expandedHeight
            )

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

                    self.manager?.setLauncherCollapsed(
                        false,
                        for: self.launcherID
                    )
                    panel.minSize = NSSize(width: 260, height: 210)
                    self.manager?.updateLauncherFrame(
                        panel.frame,
                        for: self.launcherID,
                        collapsed: false
                    )
                    self.isAnimatingCollapse = false
                }
            }

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.025
            ) { [weak self] in
                guard let self,
                      !self.store.visualCollapsed else {
                    return
                }

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
        if manager?.isCurrentWorkspaceLayoutLocked == true {
            return sender.frame.size
        }

        guard store.visualCollapsed,
              !isAnimatingCollapse else {
            return frameSize
        }

        return NSSize(
            width: max(frameSize.width, 260),
            height: Self.collapsedHeight
        )
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel, !isAnimatingCollapse else { return }

        manager?.updateLauncherFrame(
            panel.frame,
            for: launcherID,
            collapsed: store.visualCollapsed
        )
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel, !isAnimatingCollapse else { return }

        if !store.visualCollapsed {
            contentContainer?.contentHeight = panel.frame.height
        }

        manager?.updateLauncherFrame(
            panel.frame,
            for: launcherID,
            collapsed: store.visualCollapsed
        )
    }
}
