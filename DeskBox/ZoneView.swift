import SwiftUI
import AppKit
import Combine

struct ZoneView: View {
    @ObservedObject var store: ZoneStore
    @ObservedObject var selection: FileSelectionState
    @ObservedObject var workspaceState: WorkspaceState
    @State private var isDropTargeted = false

    let onCollapse: (Bool) -> Void
    let onNewZone: () -> Void
    let onNewNote: () -> Void
    let onNewChecklist: () -> Void
    let onNewLauncher: () -> Void
    let onRename: () -> Void
    let onMoveToWorkspace: (UUID) -> Void
    let onDelete: () -> Void
    let onDropURLs: ([URL]) -> Void

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
                    }
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
                .help("拖动这里移动分区")

                Menu {
                    Button("新建分区", action: onNewZone)
                    Button("新建便签", action: onNewNote)
                    Button("新建待办清单", action: onNewChecklist)
                    Button("新建快捷入口", action: onNewLauncher)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
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

                    Button("新建分区", action: onNewZone)
                    Divider()
                    Button("删除分区", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("分区设置")

                Button {
                    onCollapse(!store.visualCollapsed)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(
                            .degrees(store.visualCollapsed ? 180 : 0)
                        )
                        .animation(
                            .easeInOut(duration: 0.22),
                            value: store.visualCollapsed
                        )
                }
                .buttonStyle(.plain)
                .help(store.visualCollapsed ? "展开" : "折叠")
            }
            .frame(height: 44)
            .padding(.horizontal, 14)

            VStack(spacing: 0) {
                    Divider()
                        .opacity(0.3)

                    Group {
                        if store.files.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "arrow.down.doc")
                                    .font(.system(size: 25))
                                    .foregroundStyle(.secondary)
                                Text("把桌面文件或文件夹拖到这里")
                                    .font(.system(size: 12))
                                Text("拖入后会从桌面收纳到此分区")
                                    .font(.system(size: 11))
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
                                            _ = store.moveToDesktop(urls)
                                            selection.clear()
                                        },
                                        reorderDrop: { draggedURLs in
                                            let names = draggedURLs.map(\.lastPathComponent)
                                            let sameZone = draggedURLs.allSatisfy {
                                                $0.deletingLastPathComponent().standardizedFileURL
                                                    == store.directoryURL.standardizedFileURL
                                            }

                                            if sameZone {
                                                store.reorder(draggedURLs, before: url)
                                            } else {
                                                onDropURLs(draggedURLs)
                                                store.reorder(fileNames: names, before: url)
                                            }
                                            return true
                                        },
                                        reorderHover: { draggedURLs in
                                            let sameZone = draggedURLs.allSatisfy {
                                                $0.deletingLastPathComponent().standardizedFileURL
                                                    == store.directoryURL.standardizedFileURL
                                            }
                                            guard sameZone else { return }

                                            withAnimation(.snappy(duration: 0.16, extraBounce: 0)) {
                                                store.previewReorder(draggedURLs, before: url)
                                            }
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
        .background(isDropTargeted ? .regularMaterial : .ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isDropTargeted ? Color.accentColor : Color.white.opacity(0.18),
                    lineWidth: isDropTargeted ? 2 : 1
                )
        }
        .dropDestination(for: URL.self) { urls, _ in
            onDropURLs(urls)
            return !urls.isEmpty
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .onReceive(refreshTimer) { _ in
            store.reloadIfChanged()
        }
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
    let reorderDrop: ([URL]) -> Bool
    let reorderHover: ([URL]) -> Void
    let dragEnded: (Bool) -> Void

    @State private var isReorderTarget = false

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
                    onTargeted: { targeted in
                        isReorderTarget = targeted
                    },
                    onDragEnded: dragEnded
                )

                if isReorderTarget {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
            }
        }
        .help(url.path)
    }
}
