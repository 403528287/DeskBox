import SwiftUI
import AppKit
import Combine

struct ZoneView: View {
    @ObservedObject var store: ZoneStore
    @ObservedObject var selection: FileSelectionState
    @ObservedObject var workspaceState: WorkspaceState
    @State private var isDropTargeted = false
    @State private var fileFrames: [URL: CGRect] = [:]

    let onCollapse: (Bool) -> Void
    let onNewZone: () -> Void
    let onNewNote: () -> Void
    let onNewChecklist: () -> Void
    let onNewLauncher: () -> Void
    let onRename: () -> Void
    let onMoveToWorkspace: (UUID) -> Void
    let onDelete: () -> Void
    let onDropURLs: ([URL]) -> Void
    let onMoveToDesktopURLs: ([URL]) -> Void

    private let refreshTimer = Timer.publish(
        every: 1.0,
        on: .main,
        in: .common
    ).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    WindowDragHandle {
                        onCollapse(!store.visualCollapsed)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "tray.full.fill")
                        Text(store.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text("(\(store.files.count))")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        if store.isDirectoryMissing {
                            Image(
                                systemName: "exclamationmark.triangle.fill"
                            )
                            .font(
                                .system(
                                    size: 9,
                                    weight: .semibold
                                )
                            )
                            .foregroundStyle(
                                Color.orange.opacity(0.82)
                            )
                            .help("分区文件夹不存在")
                        }

                        if workspaceState.isCurrentLayoutLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .help("当前工作区布局已锁定")
                        }
                    }
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
                .help(
                    workspaceState.isCurrentLayoutLocked
                        ? "布局已锁定"
                        : "拖动这里移动分区"
                )

                Menu {
                    Button("新建分区", action: onNewZone)
                    Button("新建便签", action: onNewNote)
                    Button("新建待办清单", action: onNewChecklist)
                    Button("新建快捷入口", action: onNewLauncher)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                        .deskBoxHeaderHover()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("新建")

                Menu {
                    Button("重命名分区", action: onRename)

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
                    Button("删除分区", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                        .deskBoxHeaderHover()
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("分区设置")

                Button {
                    onCollapse(!store.visualCollapsed)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                        .deskBoxHeaderHover()
                        .rotationEffect(
                            .degrees(store.visualCollapsed ? 180 : 0)
                        )
                        .animation(
                            .easeInOut(duration: 0.22),
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
            .frame(height: 44)
            .padding(.horizontal, 14)

            VStack(spacing: 0) {
                    Divider()
                        .opacity(0.3)

                    Group {
                        if store.isDirectoryMissing {
                            VStack(spacing: 9) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            Color.orange.opacity(0.12)
                                        )
                                        .frame(width: 46, height: 46)

                                    Image(
                                        systemName: "exclamationmark.folder.fill"
                                    )
                                    .font(
                                        .system(
                                            size: 20,
                                            weight: .medium
                                        )
                                    )
                                    .foregroundStyle(
                                        Color.orange.opacity(0.82)
                                    )
                                }

                                Text("分区文件夹不存在")
                                    .font(
                                        .system(
                                            size: 12.5,
                                            weight: .semibold
                                        )
                                    )

                                Text(
                                    "可能已在 Finder 中被改名或移动，请恢复“\(store.name)”文件夹"
                                )
                                .font(.system(size: 10.5))
                                .foregroundStyle(
                                    Color.primary.opacity(0.58)
                                )
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 240)
                            }
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity
                            )
                            .contentShape(Rectangle())
                        } else if store.files.isEmpty {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.primary.opacity(0.045))
                                        .frame(width: 46, height: 46)

                                    Image(systemName: "tray.and.arrow.down")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }

                                Text("拖入文件开始收纳")
                                    .font(.system(size: 12.5, weight: .semibold))

                                Text("文件会移动到此分区，不会创建副本")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                        } else {
                            ScrollView {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 82), spacing: 12)],
                                    spacing: 12
                                ) {
                                    ForEach(store.files, id: \.self) { url in
                                    FileTile(
                                        url: url,
                                        isSelected: selection.isSelected(url),
                                        select: { command, shift in
                                            selection.select(
                                                url,
                                                in: store.zoneID,
                                                orderedFiles: store.files,
                                                command: command,
                                                shift: shift
                                            )
                                        },
                                        contextSelect: {
                                            selection.selectForContextMenu(
                                                url,
                                                in: store.zoneID,
                                                orderedFiles: store.files
                                            )
                                        },
                                        dragURLs: {
                                            selection.ensureSelectedForDrag(
                                                url,
                                                in: store.zoneID,
                                                orderedFiles: store.files
                                            )
                                        },
                                        contextURLs: {
                                            selection.selectedURLs(
                                                in: store.zoneID,
                                                orderedFiles: store.files
                                            )
                                        },
                                        open: { store.open(url) },
                                        preview: { QuickLookController.shared.toggle(url) },
                                        openURLs: { urls in
                                            store.open(urls)
                                        },
                                        revealURLs: { urls in
                                            store.revealInFinder(urls)
                                        },
                                        moveToDesktopURLs: { urls in
                                            onMoveToDesktopURLs(urls)
                                        },
                                        reorderDrop: { draggedURLs, after in
                                            let names = draggedURLs.map(\.lastPathComponent)
                                            let sameZone = draggedURLs.allSatisfy {
                                                $0.deletingLastPathComponent().standardizedFileURL
                                                    == store.directoryURL.standardizedFileURL
                                            }

                                            if sameZone {
                                                store.reorder(
                                                    draggedURLs,
                                                    relativeTo: url,
                                                    after: after
                                                )
                                            } else {
                                                onDropURLs(draggedURLs)
                                                store.reorder(
                                                    fileNames: names,
                                                    relativeTo: url,
                                                    after: after
                                                )
                                            }
                                            return true
                                        },
                                        reorderHover: { _, _ in
                                            // 排序在松手时一次完成。
                                            // 不在 hover 阶段修改文件数组，避免目标图标
                                            // 随实时重排不断移动，造成拖拽抖动。
                                        },
                                        dragEnded: { completed in
                                            guard !completed else { return }
                                            withAnimation(.snappy(duration: 0.16, extraBounce: 0)) {
                                                store.restoreSavedOrder()
                                            }
                                        }
                                    )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                }
                .opacity(store.contentOpacity)
                .offset(y: store.contentOffset)
        }
        .coordinateSpace(name: "DeskBox.ZoneDropSpace")
        .onPreferenceChange(FileFramePreferenceKey.self) { frames in
            fileFrames = frames
        }
        .background(isDropTargeted ? .regularMaterial : .ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isDropTargeted ? Color.accentColor : Color.white.opacity(0.18),
                    lineWidth: isDropTargeted ? 2 : 1
                )
        }
        .dropDestination(for: URL.self) { urls, location in
            guard !urls.isEmpty else { return false }

            let sameZone = urls.allSatisfy {
                $0.deletingLastPathComponent().standardizedFileURL
                    == store.directoryURL.standardizedFileURL
            }

            if sameZone {
                reorderWithinZone(
                    urls,
                    at: location
                )
            } else {
                onDropURLs(urls)
            }

            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .onReceive(refreshTimer) { _ in
            store.reloadIfChanged()
        }
    }

    private func reorderWithinZone(
        _ draggedURLs: [URL],
        at location: CGPoint
    ) {
        let draggedPaths = Set(
            draggedURLs.map { $0.standardizedFileURL.path }
        )

        let candidates = store.files.filter {
            !draggedPaths.contains(
                $0.standardizedFileURL.path
            )
        }

        let framedCandidates: [(URL, CGRect)] = candidates.compactMap {
            guard let frame = fileFrames[$0] else {
                return nil
            }
            return ($0, frame)
        }

        guard !framedCandidates.isEmpty else {
            return
        }

        let minY = framedCandidates.map { $0.1.minY }.min() ?? 0
        let maxY = framedCandidates.map { $0.1.maxY }.max() ?? 0

        if location.y < minY - 6,
           let first = framedCandidates.min(
               by: { lhs, rhs in
                   if abs(lhs.1.minY - rhs.1.minY) < 8 {
                       return lhs.1.minX < rhs.1.minX
                   }
                   return lhs.1.minY < rhs.1.minY
               }
           ) {
            store.reorder(
                draggedURLs,
                relativeTo: first.0,
                after: false
            )
            return
        }

        if location.y > maxY + 6 {
            store.reorderToEnd(draggedURLs)
            return
        }

        guard let nearest = framedCandidates.min(
            by: {
                distanceSquared(
                    from: location,
                    to: $0.1
                ) < distanceSquared(
                    from: location,
                    to: $1.1
                )
            }
        ) else {
            return
        }

        let targetURL = nearest.0
        let targetFrame = nearest.1

        let after: Bool
        if location.y < targetFrame.minY {
            after = false
        } else if location.y > targetFrame.maxY {
            after = true
        } else {
            after = location.x >= targetFrame.midX
        }

        store.reorder(
            draggedURLs,
            relativeTo: targetURL,
            after: after
        )
    }

    private func distanceSquared(
        from point: CGPoint,
        to rect: CGRect
    ) -> CGFloat {
        let dx: CGFloat
        if point.x < rect.minX {
            dx = rect.minX - point.x
        } else if point.x > rect.maxX {
            dx = point.x - rect.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < rect.minY {
            dy = rect.minY - point.y
        } else if point.y > rect.maxY {
            dy = point.y - rect.maxY
        } else {
            dy = 0
        }

        return dx * dx + dy * dy
    }
}

private struct FileFramePreferenceKey: PreferenceKey {
    static let defaultValue: [URL: CGRect] = [:]

    static func reduce(
        value: inout [URL: CGRect],
        nextValue: () -> [URL: CGRect]
    ) {
        value.merge(
            nextValue(),
            uniquingKeysWith: { _, new in new }
        )
    }
}

private struct FileTile: View {
    let url: URL
    let isSelected: Bool
    let select: (Bool, Bool) -> Void
    let contextSelect: () -> Void
    let dragURLs: () -> [URL]
    let contextURLs: () -> [URL]
    let open: () -> Void
    let preview: () -> Void
    let openURLs: ([URL]) -> Void
    let revealURLs: ([URL]) -> Void
    let moveToDesktopURLs: ([URL]) -> Void
    let reorderDrop: ([URL], Bool) -> Bool
    let reorderHover: ([URL], Bool) -> Void
    let dragEnded: (Bool) -> Void

    @State private var isReorderTarget = false
    @State private var insertAfterTarget = false

    private var icon: NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 40, height: 40)
        return image
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.16) : Color.clear)
                    .frame(width: 68, height: 58)

                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)

                Color.clear
                    .frame(width: 68, height: 58)
            }

            Text(url.lastPathComponent)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .padding(.horizontal, 3)
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: FileFramePreferenceKey.self,
                    value: [
                        url: proxy.frame(
                            in: .named(
                                "DeskBox.ZoneDropSpace"
                            )
                        )
                    ]
                )
            }
        }
        .overlay {
            ZStack {
                NativeFileDragSource(
                    url: url,
                    isSelected: isSelected,
                    onClick: select,
                    onContextClick: contextSelect,
                    dragURLs: dragURLs,
                    contextURLs: contextURLs,
                    onDoubleClick: open,
                    onPreview: preview,
                    onOpenURLs: openURLs,
                    onRevealURLs: revealURLs,
                    onMoveToDesktopURLs: moveToDesktopURLs,
                    onDropURLs: reorderDrop,
                    onHoverURLs: reorderHover,
                    onTargeted: { targeted, after in
                        isReorderTarget = targeted
                        insertAfterTarget = after
                    },
                    onDragEnded: dragEnded
                )

                if isReorderTarget {
                    HStack(spacing: 0) {
                        if insertAfterTarget {
                            Spacer(minLength: 0)
                        }

                        Capsule()
                            .fill(
                                Color.accentColor.opacity(0.72)
                            )
                            .frame(width: 2, height: 38)
                            .shadow(
                                color: Color.accentColor.opacity(0.18),
                                radius: 1
                            )

                        if !insertAfterTarget {
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, 1)
                    .allowsHitTesting(false)
                }
            }
        }
        .help(url.path)
    }
}
