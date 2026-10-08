import AppKit
import Combine
import SwiftUI
import QuartzCore

enum NoteTheme: String, Codable, CaseIterable, Equatable {
    case orange
    case yellow
    case green
    case blue
    case purple

    var title: String {
        switch self {
        case .orange: return "活力橙"
        case .yellow: return "柠檬黄"
        case .green: return "薄荷绿"
        case .blue: return "天空蓝"
        case .purple: return "薰衣草紫"
        }
    }

    var headerGradient: LinearGradient {
        LinearGradient(
            colors: headerColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var bodyGradient: LinearGradient {
        LinearGradient(
            colors: bodyColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var headerForeground: Color {
        self == .yellow
            ? Color.black.opacity(0.78)
            : Color.white.opacity(0.96)
    }

    var borderColor: Color {
        switch self {
        case .orange: return Color.orange.opacity(0.48)
        case .yellow: return Color.yellow.opacity(0.48)
        case .green: return Color.green.opacity(0.42)
        case .blue: return Color.blue.opacity(0.42)
        case .purple: return Color.purple.opacity(0.42)
        }
    }

    private var headerColors: [Color] {
        switch self {
        case .orange:
            return [
                Color(red: 1.00, green: 0.61, blue: 0.26),
                Color(red: 1.00, green: 0.42, blue: 0.14)
            ]
        case .yellow:
            return [
                Color(red: 1.00, green: 0.91, blue: 0.30),
                Color(red: 1.00, green: 0.72, blue: 0.13)
            ]
        case .green:
            return [
                Color(red: 0.33, green: 0.86, blue: 0.57),
                Color(red: 0.15, green: 0.68, blue: 0.45)
            ]
        case .blue:
            return [
                Color(red: 0.34, green: 0.72, blue: 1.00),
                Color(red: 0.20, green: 0.48, blue: 0.96)
            ]
        case .purple:
            return [
                Color(red: 0.72, green: 0.50, blue: 1.00),
                Color(red: 0.52, green: 0.31, blue: 0.91)
            ]
        }
    }

    private var bodyColors: [Color] {
        switch self {
        case .orange:
            return [
                Color(red: 1.00, green: 0.94, blue: 0.86),
                Color(red: 1.00, green: 0.86, blue: 0.70)
            ]
        case .yellow:
            return [
                Color(red: 1.00, green: 0.98, blue: 0.82),
                Color(red: 1.00, green: 0.92, blue: 0.62)
            ]
        case .green:
            return [
                Color(red: 0.91, green: 1.00, blue: 0.94),
                Color(red: 0.78, green: 0.95, blue: 0.84)
            ]
        case .blue:
            return [
                Color(red: 0.90, green: 0.96, blue: 1.00),
                Color(red: 0.78, green: 0.89, blue: 1.00)
            ]
        case .purple:
            return [
                Color(red: 0.96, green: 0.92, blue: 1.00),
                Color(red: 0.86, green: 0.78, blue: 1.00)
            ]
        }
    }
}

struct NoteConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var themeRawValue: String?
    var collapsed: Bool?
    var isPinned: Bool?

    var collapsedValue: Bool {
        get { collapsed ?? false }
        set { collapsed = newValue }
    }

    var pinnedValue: Bool {
        get { isPinned ?? false }
        set { isPinned = newValue }
    }

    var theme: NoteTheme {
        get {
            guard let themeRawValue,
                  let theme = NoteTheme(rawValue: themeRawValue) else {
                return .yellow
            }
            return theme
        }
        set {
            themeRawValue = newValue.rawValue
        }
    }
}

@MainActor
final class NoteStore: ObservableObject {
    let id: UUID

    @Published var title: String
    @Published var text: String
    @Published var theme: NoteTheme
    @Published var visualCollapsed: Bool
    @Published var isPinned: Bool
    @Published var contentOpacity: Double
    @Published var contentOffset: CGFloat

    init(config: NoteConfig) {
        id = config.id
        title = config.title
        text = config.text
        theme = config.theme
        visualCollapsed = config.collapsedValue
        isPinned = config.pinnedValue
        contentOpacity = config.collapsedValue ? 0 : 1
        contentOffset = config.collapsedValue ? -3 : 0
    }
}

struct NoteView: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var workspaceState: WorkspaceState

    let onUpdate: (String, String, NoteTheme) -> Void
    let onCollapse: (Bool) -> Void
    let onTogglePin: () -> Void
    let onMoveToWorkspace: (UUID) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                store.theme.headerGradient

                WindowDragHandle {
                    onCollapse(!store.visualCollapsed)
                }

                HStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(store.theme.headerForeground)

                    TextField("便签", text: $store.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(store.theme.headerForeground)
                        .lineLimit(1)
                        .frame(maxWidth: 150, alignment: .leading)
                        .onChange(of: store.title) { _, newValue in
                            onUpdate(
                                newValue,
                                store.text,
                                store.theme
                            )
                        }

                    Spacer(minLength: 12)

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
                    .help(store.isPinned ? "取消置顶" : "置顶便签")

                    Menu {
                        Section("便签颜色") {
                            ForEach(
                                NoteTheme.allCases,
                                id: \.rawValue
                            ) { theme in
                                Button {
                                    store.theme = theme
                                    onUpdate(
                                        store.title,
                                        store.text,
                                        theme
                                    )
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
                            store.isPinned ? "取消置顶" : "置顶便签",
                            action: onTogglePin
                        )

                        Button(
                            store.visualCollapsed ? "展开便签" : "折叠便签"
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

                        Button(
                            "删除便签",
                            role: .destructive
                        ) {
                            onDelete()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(store.theme.headerForeground)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("便签设置")

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
                    .help(store.visualCollapsed ? "展开便签" : "折叠便签")
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

            VStack(spacing: 0) {
                Divider()
                    .opacity(0.18)

                ZStack {
                    store.theme.bodyGradient

                    TextEditor(text: $store.text)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.black.opacity(0.80))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .onChange(of: store.text) { _, newValue in
                            onUpdate(
                                store.title,
                                newValue,
                                store.theme
                            )
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
        .shadow(
            color: Color.black.opacity(0.14),
            radius: 16,
            x: 0,
            y: 8
        )
    }
}

@MainActor
final class DesktopNoteController: NSObject, NSWindowDelegate {
    static let collapsedHeight: CGFloat = 42

    let noteID: UUID
    let store: NoteStore

    private weak var manager: ZoneManager?
    private var panel: DeskBoxPanel?
    private var contentContainer: TopPinnedContentView?
    private var isAnimatingCollapse = false

    init(config: NoteConfig, manager: ZoneManager) {
        noteID = config.id
        store = NoteStore(config: config)
        self.manager = manager
        super.init()
    }

    func show() {
        guard panel == nil,
              let manager,
              let config = manager.noteConfig(for: noteID) else {
            return
        }

        let expandedFrame = NSRect(
            x: config.x,
            y: config.y,
            width: max(config.width, 220),
            height: max(config.height, 160)
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
            width: 220,
            height: config.collapsedValue
                ? Self.collapsedHeight
                : 160
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

        let rootView = NoteView(
            store: store,
            workspaceState: manager.workspaceState,
            onUpdate: { [weak manager, noteID] title, text, theme in
                manager?.updateNote(
                    noteID,
                    title: title,
                    text: text,
                    theme: theme
                )
            },
            onCollapse: { [weak self] collapsed in
                self?.setCollapsed(collapsed)
            },
            onTogglePin: { [weak self] in
                self?.togglePin()
            },
            onMoveToWorkspace: { [weak manager, noteID] workspaceID in
                manager?.moveNote(
                    noteID,
                    toWorkspaceID: workspaceID
                )
            },
            onDelete: { [weak manager, noteID] in
                manager?.deleteNote(noteID)
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
        manager?.setNotePinned(store.isPinned, for: noteID)
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
              let config = manager?.noteConfig(for: noteID),
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
            manager?.updateNoteFrame(
                current,
                for: noteID,
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
                width: 220,
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

                    self.manager?.setNoteCollapsed(
                        true,
                        for: self.noteID
                    )
                    self.manager?.updateNoteFrame(
                        panel.frame,
                        for: self.noteID,
                        collapsed: true
                    )
                    self.isAnimatingCollapse = false
                }
            }
        } else {
            let current = panel.frame
            let expandedHeight = max(config.height, 160)
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

                    self.manager?.setNoteCollapsed(
                        false,
                        for: self.noteID
                    )
                    panel.minSize = NSSize(width: 220, height: 160)
                    self.manager?.updateNoteFrame(
                        panel.frame,
                        for: self.noteID,
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
            width: max(frameSize.width, 220),
            height: Self.collapsedHeight
        )
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel, !isAnimatingCollapse else { return }
        manager?.updateNoteFrame(
            panel.frame,
            for: noteID,
            collapsed: store.visualCollapsed
        )
    }

    func windowDidResize(_ notification: Notification) {
        guard let panel, !isAnimatingCollapse else { return }

        if !store.visualCollapsed {
            contentContainer?.contentHeight = panel.frame.height
        }

        manager?.updateNoteFrame(
            panel.frame,
            for: noteID,
            collapsed: store.visualCollapsed
        )
    }
}
