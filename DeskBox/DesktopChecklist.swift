import AppKit
import Combine
import SwiftUI
import QuartzCore

struct ChecklistItem: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var isDone: Bool
}

struct ChecklistConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var items: [ChecklistItem]
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
                return .green
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
final class ChecklistStore: ObservableObject {
    let id: UUID

    @Published var title: String
    @Published var items: [ChecklistItem]
    @Published var theme: NoteTheme
    @Published var visualCollapsed: Bool
    @Published var isPinned: Bool
    @Published var contentOpacity: Double
    @Published var contentOffset: CGFloat

    init(config: ChecklistConfig) {
        id = config.id
        title = config.title
        items = config.items
        theme = config.theme
        visualCollapsed = config.collapsedValue
        isPinned = config.pinnedValue
        contentOpacity = config.collapsedValue ? 0 : 1
        contentOffset = config.collapsedValue ? -3 : 0
    }

    var completedCount: Int {
        items.filter(\.isDone).count
    }

    func binding(for itemID: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.items.first(where: { $0.id == itemID })?.text ?? ""
            },
            set: { [weak self] newValue in
                guard let self,
                      let index = self.items.firstIndex(where: {
                          $0.id == itemID
                      }) else {
                    return
                }
                self.items[index].text = newValue
            }
        )
    }

    func toggle(_ itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        items[index].isDone.toggle()
    }

    func remove(_ itemID: UUID) {
        items.removeAll(where: { $0.id == itemID })
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return }

        items.append(
            ChecklistItem(
                id: UUID(),
                text: trimmed,
                isDone: false
            )
        )
    }
}

struct ChecklistView: View {
    @ObservedObject var store: ChecklistStore
    @ObservedObject var workspaceState: WorkspaceState
    @State private var draftText = ""

    let onUpdate: (String, [ChecklistItem], NoteTheme) -> Void
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

                    VStack(spacing: 8) {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(store.items) { item in
                                    checklistRow(item)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                        }

                        addRow
                            .padding(.horizontal, 10)
                            .padding(.bottom, 10)
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
            .stroke(
                store.theme.borderColor,
                lineWidth: 1
            )
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
                Image(systemName: "checklist")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(store.theme.headerForeground)

                TextField("待办清单", text: $store.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(store.theme.headerForeground)
                    .lineLimit(1)
                    .frame(maxWidth: 145, alignment: .leading)
                    .onChange(of: store.title) { _, _ in
                        persist()
                    }

                if !store.items.isEmpty {
                    Text("\(store.completedCount)/\(store.items.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            store.theme.headerForeground.opacity(0.72)
                        )
                }

                Spacer(minLength: 8)

                Button(action: onTogglePin) {
                    Image(
                        systemName: store.isPinned
                            ? "pin.fill"
                            : "pin"
                    )
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.theme.headerForeground)
                    .rotationEffect(.degrees(store.isPinned ? 0 : -20))
                }
                .buttonStyle(.plain)
                .help(store.isPinned ? "取消置顶" : "置顶清单")

                Menu {
                    Section("清单颜色") {
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
                        store.isPinned ? "取消置顶" : "置顶清单",
                        action: onTogglePin
                    )

                    Button(
                        store.visualCollapsed ? "展开清单" : "折叠清单"
                    ) {
                        onCollapse(!store.visualCollapsed)
                    }

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

                    Button("删除清单", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(store.theme.headerForeground)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("清单设置")

                Button {
                    onCollapse(!store.visualCollapsed)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(store.theme.headerForeground)
                        .rotationEffect(
                            .degrees(store.visualCollapsed ? 180 : 0)
                        )
                        .animation(
                            .easeInOut(duration: 0.20),
                            value: store.visualCollapsed
                        )
                }
                .buttonStyle(.plain)
                .help(store.visualCollapsed ? "展开清单" : "折叠清单")
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

    @ViewBuilder
    private func checklistRow(_ item: ChecklistItem) -> some View {
        HStack(spacing: 8) {
            Button {
                store.toggle(item.id)
                persist()
            } label: {
                Image(
                    systemName: item.isDone
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                item.isDone
                    ? Color.black.opacity(0.38)
                    : Color.black.opacity(0.66)
            )

            TextField(
                "待办事项",
                text: store.binding(for: item.id)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(
                item.isDone
                    ? Color.black.opacity(0.42)
                    : Color.black.opacity(0.82)
            )
            .strikethrough(item.isDone)
            .onChange(of: store.items) { _, _ in
                persist()
            }

            Button {
                store.remove(item.id)
                persist()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.28))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("删除")
        }
        .padding(.horizontal, 9)
        .frame(minHeight: 32)
        .background(
            RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
            )
            .fill(Color.white.opacity(item.isDone ? 0.22 : 0.40))
        )
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color.black.opacity(0.42))

            TextField("添加待办…", text: $draftText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit {
                    addDraft()
                }

            Button("添加") {
                addDraft()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.55))
        }
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(
            RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
            .fill(Color.white.opacity(0.34))
        )
    }

    private func addDraft() {
        let before = store.items.count
        store.add(draftText)
        guard store.items.count != before else { return }
        draftText = ""
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
final class DesktopChecklistController: NSObject, NSWindowDelegate {
    static let collapsedHeight: CGFloat = 42

    let checklistID: UUID
    let store: ChecklistStore

    private weak var manager: ZoneManager?
    private var panel: DeskBoxPanel?
    private var contentContainer: TopPinnedContentView?
    private var isAnimatingCollapse = false

    init(config: ChecklistConfig, manager: ZoneManager) {
        checklistID = config.id
        store = ChecklistStore(config: config)
        self.manager = manager
        super.init()
    }

    func show() {
        guard panel == nil,
              let manager,
              let config = manager.checklistConfig(for: checklistID) else {
            return
        }

        let expandedFrame = NSRect(
            x: config.x,
            y: config.y,
            width: max(config.width, 240),
            height: max(config.height, 190)
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
            width: 240,
            height: config.collapsedValue
                ? Self.collapsedHeight
                : 190
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

        let rootView = ChecklistView(
            store: store,
            workspaceState: manager.workspaceState,
            onUpdate: { [weak manager, checklistID] title, items, theme in
                manager?.updateChecklist(
                    checklistID,
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
            onMoveToWorkspace: { [weak manager, checklistID] workspaceID in
                manager?.moveChecklist(
                    checklistID,
                    toWorkspaceID: workspaceID
                )
            },
            onDelete: { [weak manager, checklistID] in
                manager?.deleteChecklist(checklistID)
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

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        contentContainer = nil
    }

    private func togglePin() {
        store.isPinned.toggle()
        manager?.setChecklistPinned(
            store.isPinned,
            for: checklistID
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
        guard let panel,
              let config = manager?.checklistConfig(for: checklistID),
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
            manager?.updateChecklistFrame(
                current,
                for: checklistID,
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
                width: 240,
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

                    self.manager?.setChecklistCollapsed(
                        true,
                        for: self.checklistID
                    )
                    self.manager?.updateChecklistFrame(
                        panel.frame,
                        for: self.checklistID,
                        collapsed: true
                    )
                    self.isAnimatingCollapse = false
                }
            }
        } else {
            let current = panel.frame
            let expandedHeight = max(config.height, 190)
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

                    self.manager?.setChecklistCollapsed(
                        false,
                        for: self.checklistID
                    )
                    panel.minSize = NSSize(width: 240, height: 190)
                    self.manager?.updateChecklistFrame(
                        panel.frame,
                        for: self.checklistID,
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
        guard store.visualCollapsed,
              !isAnimatingCollapse else {
            return frameSize
        }

        return NSSize(
            width: max(frameSize.width, 240),
            height: Self.collapsedHeight
        )
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel, !isAnimatingCollapse else { return }
        manager?.updateChecklistFrame(
            panel.frame,
            for: checklistID,
            collapsed: store.visualCollapsed
        )
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel, !isAnimatingCollapse else { return }

        if !store.visualCollapsed {
            contentContainer?.contentHeight = panel.frame.height
        }

        manager?.updateChecklistFrame(
            panel.frame,
            for: checklistID,
            collapsed: store.visualCollapsed
        )
    }
}
