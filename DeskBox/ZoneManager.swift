import AppKit
import Combine

@MainActor
final class FileSelectionState: ObservableObject {
    @Published private(set) var selectedPaths: Set<String> = []
    private(set) var selectedZoneID: UUID?
    private var anchorPath: String?

    var count: Int {
        selectedPaths.count
    }

    func select(
        _ url: URL,
        in zoneID: UUID,
        orderedFiles: [URL],
        command: Bool = false,
        shift: Bool = false
    ) {
        let path = url.standardizedFileURL.path

        if shift,
           selectedZoneID == zoneID,
           let anchorPath,
           let anchorIndex = orderedFiles.firstIndex(where: {
               $0.standardizedFileURL.path == anchorPath
           }),
           let targetIndex = orderedFiles.firstIndex(where: {
               $0.standardizedFileURL.path == path
           }) {
            let lower = min(anchorIndex, targetIndex)
            let upper = max(anchorIndex, targetIndex)
            let rangePaths = Set(
                orderedFiles[lower...upper].map {
                    $0.standardizedFileURL.path
                }
            )

            selectedZoneID = zoneID
            if command {
                selectedPaths.formUnion(rangePaths)
            } else {
                selectedPaths = rangePaths
            }
            return
        }

        if command, selectedZoneID == zoneID {
            if selectedPaths.contains(path) {
                selectedPaths.remove(path)
                if selectedPaths.isEmpty {
                    selectedZoneID = nil
                    anchorPath = nil
                }
            } else {
                selectedPaths.insert(path)
                anchorPath = path
            }
            return
        }

        selectedZoneID = zoneID
        selectedPaths = [path]
        anchorPath = path
    }

    func ensureSelectedForDrag(
        _ url: URL,
        in zoneID: UUID,
        orderedFiles: [URL]
    ) -> [URL] {
        let path = url.standardizedFileURL.path

        if selectedZoneID != zoneID || !selectedPaths.contains(path) {
            selectedZoneID = zoneID
            selectedPaths = [path]
            anchorPath = path
            return [url]
        }

        return orderedFiles.filter { candidate in
            selectedPaths.contains(candidate.standardizedFileURL.path)
        }
    }

    func selectForContextMenu(
        _ url: URL,
        in zoneID: UUID,
        orderedFiles: [URL]
    ) {
        let path = url.standardizedFileURL.path
        guard selectedZoneID == zoneID,
              selectedPaths.contains(path) else {
            select(
                url,
                in: zoneID,
                orderedFiles: orderedFiles
            )
            return
        }
    }

    func selectedURLs(
        in zoneID: UUID,
        orderedFiles: [URL]
    ) -> [URL] {
        guard selectedZoneID == zoneID else { return [] }

        return orderedFiles.filter { candidate in
            selectedPaths.contains(candidate.standardizedFileURL.path)
        }
    }

    func clear() {
        selectedPaths.removeAll()
        selectedZoneID = nil
        anchorPath = nil
    }

    func isSelected(_ url: URL) -> Bool {
        selectedPaths.contains(url.standardizedFileURL.path)
    }
}

struct ZoneConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var collapsed: Bool
}

struct WorkspaceConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
}

@MainActor
final class WorkspaceState: ObservableObject {
    @Published var workspaces: [WorkspaceConfig] = []
    @Published var currentID = UUID()
}

@MainActor
final class ZoneManager {
    private let zonesKey = "DeskBox.Zones.v1"
    private let notesKey = "DeskBox.Notes.v1"
    private let checklistsKey = "DeskBox.Checklists.v1"
    private let launchersKey = "DeskBox.Launchers.v1"

    private let workspacesKey = "DeskBox.Workspaces.v1"
    private let currentWorkspaceKey = "DeskBox.CurrentWorkspace.v1"
    private let zoneWorkspaceKey = "DeskBox.ZoneWorkspace.v1"
    private let noteWorkspaceKey = "DeskBox.NoteWorkspace.v1"
    private let checklistWorkspaceKey = "DeskBox.ChecklistWorkspace.v1"
    private let launcherWorkspaceKey = "DeskBox.LauncherWorkspace.v1"

    private var zones: [ZoneConfig] = []
    private var controllers: [UUID: DesktopZoneController] = [:]
    private var notes: [NoteConfig] = []
    private var noteControllers: [UUID: DesktopNoteController] = [:]
    private var checklists: [ChecklistConfig] = []
    private var checklistControllers: [UUID: DesktopChecklistController] = [:]
    private var launchers: [LauncherConfig] = []
    private var launcherControllers: [UUID: DesktopLauncherController] = [:]

    private var workspaces: [WorkspaceConfig] = []
    private(set) var currentWorkspaceID = UUID()

    private var zoneWorkspace: [String: String] = [:]
    private var noteWorkspace: [String: String] = [:]
    private var checklistWorkspace: [String: String] = [:]
    private var launcherWorkspace: [String: String] = [:]

    let selectionState = FileSelectionState()
    let workspaceState = WorkspaceState()
    private(set) var areZonesHidden = false
    private let storageRoot: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageRoot = documents.appendingPathComponent("DeskBox", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: storageRoot,
                withIntermediateDirectories: true
            )
        } catch {
            NSLog("DeskBox storage root create failed: \(error)")
        }

        workspaces = loadWorkspaces()
        if workspaces.isEmpty {
            workspaces = [
                WorkspaceConfig(
                    id: UUID(),
                    name: "日常"
                )
            ]
            saveWorkspaces()
        }

        if let storedID = loadCurrentWorkspaceID(),
           workspaces.contains(where: { $0.id == storedID }) {
            currentWorkspaceID = storedID
        } else {
            currentWorkspaceID = defaultWorkspaceID
            saveCurrentWorkspaceID()
        }

        zoneWorkspace = loadWorkspaceMap(forKey: zoneWorkspaceKey)
        noteWorkspace = loadWorkspaceMap(forKey: noteWorkspaceKey)
        checklistWorkspace = loadWorkspaceMap(forKey: checklistWorkspaceKey)
        launcherWorkspace = loadWorkspaceMap(forKey: launcherWorkspaceKey)

        zones = loadZones()
        notes = loadNotes()
        checklists = loadChecklists()
        launchers = loadLaunchers()

        if zones.isEmpty {
            zones = makeInitialZones()
            saveZones()
        }

        ensureWorkspaceAssignments()
        syncWorkspaceState()
        ensureZoneFolders()
        migrateLegacyReferences()
    }

    var currentWorkspaceName: String {
        workspaces.first(where: { $0.id == currentWorkspaceID })?.name
            ?? "日常"
    }

    func workspaceList() -> [WorkspaceConfig] {
        workspaces
    }

    func workspaceItemCount(_ id: UUID) -> Int {
        let value = id.uuidString
        return zoneWorkspace.values.filter { $0 == value }.count
            + noteWorkspace.values.filter { $0 == value }.count
            + checklistWorkspace.values.filter { $0 == value }.count
            + launcherWorkspace.values.filter { $0 == value }.count
    }

    func renameCurrentWorkspace() {
        guard let index = workspaces.firstIndex(where: {
            $0.id == currentWorkspaceID
        }) else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "重命名工作区"
        alert.informativeText = "输入新的工作区名称"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 280, height: 26)
        )
        field.stringValue = workspaces[index].name
        field.selectText(nil)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let name = field.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !name.isEmpty else {
            NSSound.beep()
            return
        }

        guard !workspaces.contains(where: {
            $0.id != currentWorkspaceID
                && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            showError("工作区名称已存在", "请换一个名称。")
            return
        }

        workspaces[index].name = name
        saveWorkspaces()
        syncWorkspaceState()
    }

    func moveZone(_ id: UUID, toWorkspaceID workspaceID: UUID) {
        guard workspaces.contains(where: { $0.id == workspaceID }) else {
            return
        }
        zoneWorkspace[id.uuidString] = workspaceID.uuidString
        finishWorkspaceMove()
    }

    func moveNote(_ id: UUID, toWorkspaceID workspaceID: UUID) {
        guard workspaces.contains(where: { $0.id == workspaceID }) else {
            return
        }
        noteWorkspace[id.uuidString] = workspaceID.uuidString
        finishWorkspaceMove()
    }

    func moveChecklist(_ id: UUID, toWorkspaceID workspaceID: UUID) {
        guard workspaces.contains(where: { $0.id == workspaceID }) else {
            return
        }
        checklistWorkspace[id.uuidString] = workspaceID.uuidString
        finishWorkspaceMove()
    }

    func moveLauncher(_ id: UUID, toWorkspaceID workspaceID: UUID) {
        guard workspaces.contains(where: { $0.id == workspaceID }) else {
            return
        }
        launcherWorkspace[id.uuidString] = workspaceID.uuidString
        finishWorkspaceMove()
    }

    func showAll() {
        areZonesHidden = false
        applyCurrentWorkspaceVisibility()
    }

    func hideAll() {
        areZonesHidden = true
        for (_, controller) in controllers {
            controller.hideWindow()
        }
        for (_, controller) in noteControllers {
            controller.hideWindow()
        }
        for (_, controller) in checklistControllers {
            controller.hideWindow()
        }
        for (_, controller) in launcherControllers {
            controller.hideWindow()
        }
    }

    @discardableResult
    func toggleAllVisibility() -> Bool {
        if areZonesHidden {
            showAll()
        } else {
            hideAll()
        }
        return !areZonesHidden
    }

    func openStorageFolder() {
        NSWorkspace.shared.open(storageRoot)
    }

    func switchWorkspace(to id: UUID) {
        guard workspaces.contains(where: { $0.id == id }),
              id != currentWorkspaceID else {
            return
        }

        selectionState.clear()
        currentWorkspaceID = id
        saveCurrentWorkspaceID()
        syncWorkspaceState()

        if !areZonesHidden {
            applyCurrentWorkspaceVisibility()
        }
    }

    func createWorkspace() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "新建工作区"
        alert.informativeText = "输入工作区名称"
        alert.addButton(withTitle: "创建")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 280, height: 26)
        )
        field.placeholderString = "例如：投标项目"
        alert.accessoryView = field
        field.becomeFirstResponder()

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let name = field.stringValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !name.isEmpty else {
            NSSound.beep()
            return
        }

        guard !workspaces.contains(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            showError("工作区名称已存在", "请换一个名称。")
            return
        }

        let workspace = WorkspaceConfig(
            id: UUID(),
            name: name
        )

        workspaces.append(workspace)
        saveWorkspaces()

        currentWorkspaceID = workspace.id
        saveCurrentWorkspaceID()
        syncWorkspaceState()
        selectionState.clear()

        if !areZonesHidden {
            applyCurrentWorkspaceVisibility()
        }
    }

    func deleteCurrentWorkspace() {
        guard workspaces.count > 1,
              let current = workspaces.first(where: {
                  $0.id == currentWorkspaceID
              }) else {
            NSSound.beep()
            return
        }

        let target = workspaces.first(where: {
            $0.id != currentWorkspaceID && $0.name == "日常"
        }) ?? workspaces.first(where: {
            $0.id != currentWorkspaceID
        })!

        let itemCount = workspaceItemCount(current.id)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除“\(current.name)”工作区？"

        if itemCount > 0 {
            alert.informativeText = """
            其中的 \(itemCount) 个分区或组件会移到“\(target.name)”。

            这只改变 DeskBox 的归属关系，不会移动或删除任何真实文件。
            """
        } else {
            alert.informativeText = "这个工作区是空的。"
        }

        alert.addButton(withTitle: "删除工作区")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        moveWorkspaceAssignments(
            from: current.id,
            to: target.id
        )

        workspaces.removeAll(where: { $0.id == current.id })
        currentWorkspaceID = target.id

        saveWorkspaces()
        saveCurrentWorkspaceID()
        saveWorkspaceAssignments()
        syncWorkspaceState()
        selectionState.clear()

        if !areZonesHidden {
            applyCurrentWorkspaceVisibility()
        }
    }

    func createZone() {
        let frame = nextFrame()
        let zone = ZoneConfig(
            id: UUID(),
            name: uniqueZoneName(base: "新分区"),
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: frame.height,
            collapsed: false
        )

        zones.append(zone)
        zoneWorkspace[zone.id.uuidString] = currentWorkspaceID.uuidString
        createFolderIfNeeded(for: zone)
        saveZones()
        saveWorkspaceAssignments()
        show(zone)
        promptRename(zone.id)
    }

    func createNote() {
        let frame = nextNoteFrame()
        let themes = NoteTheme.allCases
        let theme = themes[notes.count % themes.count]

        let note = NoteConfig(
            id: UUID(),
            title: "新便签",
            text: "",
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: frame.height,
            themeRawValue: theme.rawValue,
            collapsed: false,
            isPinned: false
        )

        notes.append(note)
        noteWorkspace[note.id.uuidString] = currentWorkspaceID.uuidString
        saveNotes()
        saveWorkspaceAssignments()
        show(note)
    }

    func createChecklist() {
        let frame = nextChecklistFrame()
        let themes = NoteTheme.allCases
        let theme = themes[(checklists.count + 2) % themes.count]

        let checklist = ChecklistConfig(
            id: UUID(),
            title: "今日待办",
            items: [],
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: frame.height,
            themeRawValue: theme.rawValue,
            collapsed: false,
            isPinned: false
        )

        checklists.append(checklist)
        checklistWorkspace[checklist.id.uuidString] = currentWorkspaceID.uuidString
        saveChecklists()
        saveWorkspaceAssignments()
        show(checklist)
    }

    func createLauncher() {
        let frame = nextLauncherFrame()
        let themes = NoteTheme.allCases
        let theme = themes[(launchers.count + 3) % themes.count]

        let launcher = LauncherConfig(
            id: UUID(),
            title: "快捷入口",
            items: [],
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: frame.height,
            themeRawValue: theme.rawValue,
            collapsed: false,
            isPinned: false
        )

        launchers.append(launcher)
        launcherWorkspace[launcher.id.uuidString] = currentWorkspaceID.uuidString
        saveLaunchers()
        saveWorkspaceAssignments()
        show(launcher)
    }

    func promptRename(_ id: UUID) {
        guard let index = zones.firstIndex(where: { $0.id == id }) else { return }

        let alert = NSAlert()
        alert.messageText = "重命名分区"
        alert.informativeText = "输入新的分区名称"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        field.stringValue = zones[index].name
        field.selectText(nil)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if zones.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            showError("分区名称已存在", "请换一个名称。")
            return
        }

        let oldURL = folderURL(for: zones[index])
        var updated = zones[index]
        updated.name = name
        let newURL = folderURL(for: updated)

        if oldURL.standardizedFileURL != newURL.standardizedFileURL {
            if FileManager.default.fileExists(atPath: newURL.path) {
                showError("无法重命名", "目标文件夹已经存在：\(newURL.lastPathComponent)")
                return
            }

            do {
                if FileManager.default.fileExists(atPath: oldURL.path) {
                    try FileManager.default.moveItem(at: oldURL, to: newURL)
                } else {
                    try FileManager.default.createDirectory(
                        at: newURL,
                        withIntermediateDirectories: true
                    )
                }
            } catch {
                showError("重命名失败", error.localizedDescription)
                return
            }
        }

        zones[index] = updated
        controllers[id]?.rename(to: name, directoryURL: newURL)
        saveZones()
    }

    func deleteZone(_ id: UUID) {
        guard zones.count > 1,
              let index = zones.firstIndex(where: { $0.id == id }) else {
            NSSound.beep()
            return
        }

        let zone = zones[index]
        let folder = folderURL(for: zone)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        let alert = NSAlert()
        alert.messageText = "删除“\(zone.name)”？"

        if contents.isEmpty {
            alert.informativeText = "这个分区是空的。"
            alert.addButton(withTitle: "删除分区")
        } else {
            alert.informativeText = "其中有 \(contents.count) 个项目。删除分区前会先把这些文件移回桌面，不会删除任何文件。"
            alert.addButton(withTitle: "移回桌面并删除")
        }

        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if !contents.isEmpty {
            guard moveURLsToDesktop(contents) else {
                showError("删除分区失败", "有文件未能移回桌面，分区没有被删除。")
                controllers[id]?.store.reload()
                return
            }
        }

        do {
            if FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.removeItem(at: folder)
            }
        } catch {
            showError("删除文件夹失败", error.localizedDescription)
            return
        }

        controllers[id]?.close()
        controllers[id] = nil
        zones.remove(at: index)
        zoneWorkspace.removeValue(forKey: id.uuidString)
        UserDefaults.standard.removeObject(forKey: ZoneStore.legacyFilesKey(for: id))
        saveZones()
        saveWorkspaceAssignments()
    }

    func moveFiles(_ urls: [URL], to destinationID: UUID) {
        guard let destination = controllers[destinationID] else { return }

        let succeeded = destination.store.moveIntoZone(urls)

        for (_, controller) in controllers {
            controller.store.reload()
        }

        if !succeeded {
            showError("有文件未能移动", "请检查文件是否正在被其他程序占用，或是否有访问权限。")
        }
    }

    func config(for id: UUID) -> ZoneConfig? {
        zones.first(where: { $0.id == id })
    }

    func noteConfig(for id: UUID) -> NoteConfig? {
        notes.first(where: { $0.id == id })
    }

    func checklistConfig(for id: UUID) -> ChecklistConfig? {
        checklists.first(where: { $0.id == id })
    }

    func launcherConfig(for id: UUID) -> LauncherConfig? {
        launchers.first(where: { $0.id == id })
    }

    func updateLauncher(
        _ id: UUID,
        title: String,
        items: [LauncherItem],
        theme: NoteTheme
    ) {
        guard let index = launchers.firstIndex(where: { $0.id == id }) else {
            return
        }

        launchers[index].title = title
        launchers[index].items = items
        launchers[index].theme = theme
        saveLaunchers()
    }

    func setLauncherCollapsed(_ collapsed: Bool, for id: UUID) {
        guard let index = launchers.firstIndex(where: { $0.id == id }) else {
            return
        }

        launchers[index].collapsedValue = collapsed
        saveLaunchers()
    }

    func setLauncherPinned(_ pinned: Bool, for id: UUID) {
        guard let index = launchers.firstIndex(where: { $0.id == id }) else {
            return
        }

        launchers[index].pinnedValue = pinned
        saveLaunchers()
    }

    func updateLauncherFrame(
        _ frame: NSRect,
        for id: UUID,
        collapsed: Bool
    ) {
        guard let index = launchers.firstIndex(where: { $0.id == id }) else {
            return
        }

        launchers[index].x = frame.minX
        launchers[index].width = max(frame.width, 260)

        if collapsed {
            let expandedHeight = max(launchers[index].height, 210)
            launchers[index].y = frame.maxY - expandedHeight
        } else {
            launchers[index].y = frame.minY
            launchers[index].height = max(frame.height, 210)
        }

        saveLaunchers()
    }

    func deleteLauncher(_ id: UUID) {
        guard let index = launchers.firstIndex(where: { $0.id == id }) else {
            return
        }

        let launcher = launchers[index]
        if !launcher.items.isEmpty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "删除“\(launcher.title)”？"
            alert.informativeText = "其中有 \(launcher.items.count) 个快捷入口。只会删除快捷方式，不会删除原文件或应用。"
            alert.addButton(withTitle: "删除")
            alert.addButton(withTitle: "取消")

            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
        }

        launcherControllers[id]?.close()
        launcherControllers[id] = nil
        launchers.remove(at: index)
        launcherWorkspace.removeValue(forKey: id.uuidString)
        saveLaunchers()
        saveWorkspaceAssignments()
    }

    func updateChecklist(
        _ id: UUID,
        title: String,
        items: [ChecklistItem],
        theme: NoteTheme
    ) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else {
            return
        }

        checklists[index].title = title
        checklists[index].items = items
        checklists[index].theme = theme
        saveChecklists()
    }

    func setChecklistCollapsed(_ collapsed: Bool, for id: UUID) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else {
            return
        }

        checklists[index].collapsedValue = collapsed
        saveChecklists()
    }

    func setChecklistPinned(_ pinned: Bool, for id: UUID) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else {
            return
        }

        checklists[index].pinnedValue = pinned
        saveChecklists()
    }

    func updateChecklistFrame(
        _ frame: NSRect,
        for id: UUID,
        collapsed: Bool
    ) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else {
            return
        }

        checklists[index].x = frame.minX
        checklists[index].width = max(frame.width, 240)

        if collapsed {
            let expandedHeight = max(checklists[index].height, 190)
            checklists[index].y = frame.maxY - expandedHeight
        } else {
            checklists[index].y = frame.minY
            checklists[index].height = max(frame.height, 190)
        }

        saveChecklists()
    }

    func deleteChecklist(_ id: UUID) {
        guard let index = checklists.firstIndex(where: { $0.id == id }) else {
            return
        }

        let checklist = checklists[index]
        if !checklist.items.isEmpty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "删除“\(checklist.title)”？"
            alert.informativeText = "这个清单里还有 \(checklist.items.count) 个待办事项。"
            alert.addButton(withTitle: "删除")
            alert.addButton(withTitle: "取消")

            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
        }

        checklistControllers[id]?.close()
        checklistControllers[id] = nil
        checklists.remove(at: index)
        checklistWorkspace.removeValue(forKey: id.uuidString)
        saveChecklists()
        saveWorkspaceAssignments()
    }

    func updateNote(
        _ id: UUID,
        title: String,
        text: String,
        theme: NoteTheme
    ) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            return
        }

        notes[index].title = title
        notes[index].text = text
        notes[index].theme = theme
        saveNotes()
    }

    func setNoteCollapsed(_ collapsed: Bool, for id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            return
        }
        notes[index].collapsedValue = collapsed
        saveNotes()
    }

    func setNotePinned(_ pinned: Bool, for id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            return
        }
        notes[index].pinnedValue = pinned
        saveNotes()
    }

    func updateNoteFrame(
        _ frame: NSRect,
        for id: UUID,
        collapsed: Bool
    ) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            return
        }

        notes[index].x = frame.minX
        notes[index].width = max(frame.width, 220)

        if collapsed {
            let expandedHeight = max(notes[index].height, 160)
            notes[index].y = frame.maxY - expandedHeight
        } else {
            notes[index].y = frame.minY
            notes[index].height = max(frame.height, 160)
        }

        saveNotes()
    }

    func deleteNote(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            return
        }

        let note = notes[index]
        if !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "删除“\(note.title)”？"
            alert.informativeText = "便签内容会被永久删除。"
            alert.addButton(withTitle: "删除")
            alert.addButton(withTitle: "取消")

            guard alert.runModal() == .alertFirstButtonReturn else {
                return
            }
        }

        noteControllers[id]?.close()
        noteControllers[id] = nil
        notes.remove(at: index)
        noteWorkspace.removeValue(forKey: id.uuidString)
        saveNotes()
        saveWorkspaceAssignments()
    }

    func directoryURL(for id: UUID) -> URL? {
        guard let zone = config(for: id) else { return nil }
        return folderURL(for: zone)
    }

    func setCollapsed(_ collapsed: Bool, for id: UUID) {
        guard let index = zones.firstIndex(where: { $0.id == id }) else { return }
        zones[index].collapsed = collapsed
        saveZones()
    }

    func updateFrame(_ frame: NSRect, for id: UUID, collapsed: Bool) {
        guard let index = zones.firstIndex(where: { $0.id == id }) else { return }

        zones[index].x = frame.minX
        zones[index].width = frame.width

        if collapsed {
            let expandedHeight = zones[index].height
            zones[index].y = frame.maxY - expandedHeight
        } else {
            zones[index].y = frame.minY
            zones[index].height = max(frame.height, 150)
        }

        saveZones()
    }

    private var defaultWorkspaceID: UUID {
        workspaces.first(where: { $0.name == "日常" })?.id
            ?? workspaces.first!.id
    }

    private func applyCurrentWorkspaceVisibility() {
        for (_, controller) in controllers {
            controller.hideWindow()
        }
        for (_, controller) in noteControllers {
            controller.hideWindow()
        }
        for (_, controller) in checklistControllers {
            controller.hideWindow()
        }
        for (_, controller) in launcherControllers {
            controller.hideWindow()
        }

        guard !areZonesHidden else { return }

        for zone in zones where isInCurrentWorkspace(
            zone.id,
            map: zoneWorkspace
        ) {
            if let controller = controllers[zone.id] {
                controller.showWindow()
            } else {
                show(zone)
            }
        }

        for note in notes where isInCurrentWorkspace(
            note.id,
            map: noteWorkspace
        ) {
            if let controller = noteControllers[note.id] {
                controller.showWindow()
            } else {
                show(note)
            }
        }

        for checklist in checklists where isInCurrentWorkspace(
            checklist.id,
            map: checklistWorkspace
        ) {
            if let controller = checklistControllers[checklist.id] {
                controller.showWindow()
            } else {
                show(checklist)
            }
        }

        for launcher in launchers where isInCurrentWorkspace(
            launcher.id,
            map: launcherWorkspace
        ) {
            if let controller = launcherControllers[launcher.id] {
                controller.showWindow()
            } else {
                show(launcher)
            }
        }
    }

    private func isInCurrentWorkspace(
        _ id: UUID,
        map: [String: String]
    ) -> Bool {
        map[id.uuidString] == currentWorkspaceID.uuidString
    }

    private func finishWorkspaceMove() {
        saveWorkspaceAssignments()
        syncWorkspaceState()
        selectionState.clear()

        if !areZonesHidden {
            applyCurrentWorkspaceVisibility()
        }
    }

    private func syncWorkspaceState() {
        workspaceState.workspaces = workspaces
        workspaceState.currentID = currentWorkspaceID
    }

    private func moveWorkspaceAssignments(
        from sourceID: UUID,
        to destinationID: UUID
    ) {
        let source = sourceID.uuidString
        let destination = destinationID.uuidString

        for key in Array(zoneWorkspace.keys)
            where zoneWorkspace[key] == source {
            zoneWorkspace[key] = destination
        }
        for key in Array(noteWorkspace.keys)
            where noteWorkspace[key] == source {
            noteWorkspace[key] = destination
        }
        for key in Array(checklistWorkspace.keys)
            where checklistWorkspace[key] == source {
            checklistWorkspace[key] = destination
        }
        for key in Array(launcherWorkspace.keys)
            where launcherWorkspace[key] == source {
            launcherWorkspace[key] = destination
        }
    }

    private func ensureWorkspaceAssignments() {
        let validWorkspaces = Set(
            workspaces.map { $0.id.uuidString }
        )
        let fallback = defaultWorkspaceID.uuidString

        let zoneIDs = Set(zones.map { $0.id.uuidString })
        let noteIDs = Set(notes.map { $0.id.uuidString })
        let checklistIDs = Set(checklists.map { $0.id.uuidString })
        let launcherIDs = Set(launchers.map { $0.id.uuidString })

        zoneWorkspace = zoneWorkspace.filter {
            zoneIDs.contains($0.key)
                && validWorkspaces.contains($0.value)
        }
        noteWorkspace = noteWorkspace.filter {
            noteIDs.contains($0.key)
                && validWorkspaces.contains($0.value)
        }
        checklistWorkspace = checklistWorkspace.filter {
            checklistIDs.contains($0.key)
                && validWorkspaces.contains($0.value)
        }
        launcherWorkspace = launcherWorkspace.filter {
            launcherIDs.contains($0.key)
                && validWorkspaces.contains($0.value)
        }

        for zone in zones where zoneWorkspace[zone.id.uuidString] == nil {
            zoneWorkspace[zone.id.uuidString] = fallback
        }
        for note in notes where noteWorkspace[note.id.uuidString] == nil {
            noteWorkspace[note.id.uuidString] = fallback
        }
        for checklist in checklists
            where checklistWorkspace[checklist.id.uuidString] == nil {
            checklistWorkspace[checklist.id.uuidString] = fallback
        }
        for launcher in launchers
            where launcherWorkspace[launcher.id.uuidString] == nil {
            launcherWorkspace[launcher.id.uuidString] = fallback
        }

        saveWorkspaceAssignments()
    }

    private func loadWorkspaces() -> [WorkspaceConfig] {
        guard let data = UserDefaults.standard.data(forKey: workspacesKey),
              let decoded = try? JSONDecoder().decode(
                  [WorkspaceConfig].self,
                  from: data
              ) else {
            return []
        }
        return decoded
    }

    private func saveWorkspaces() {
        guard let data = try? JSONEncoder().encode(workspaces) else {
            return
        }
        UserDefaults.standard.set(data, forKey: workspacesKey)
    }

    private func loadCurrentWorkspaceID() -> UUID? {
        guard let value = UserDefaults.standard.string(
            forKey: currentWorkspaceKey
        ) else {
            return nil
        }
        return UUID(uuidString: value)
    }

    private func saveCurrentWorkspaceID() {
        UserDefaults.standard.set(
            currentWorkspaceID.uuidString,
            forKey: currentWorkspaceKey
        )
    }

    private func loadWorkspaceMap(
        forKey key: String
    ) -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(
                  [String: String].self,
                  from: data
              ) else {
            return [:]
        }
        return decoded
    }

    private func saveWorkspaceAssignments() {
        saveWorkspaceMap(zoneWorkspace, forKey: zoneWorkspaceKey)
        saveWorkspaceMap(noteWorkspace, forKey: noteWorkspaceKey)
        saveWorkspaceMap(
            checklistWorkspace,
            forKey: checklistWorkspaceKey
        )
        saveWorkspaceMap(
            launcherWorkspace,
            forKey: launcherWorkspaceKey
        )
    }

    private func saveWorkspaceMap(
        _ map: [String: String],
        forKey key: String
    ) {
        guard let data = try? JSONEncoder().encode(map) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func show(_ zone: ZoneConfig) {
        guard controllers[zone.id] == nil else { return }

        let controller = DesktopZoneController(
            config: zone,
            directoryURL: folderURL(for: zone),
            manager: self
        )
        controllers[zone.id] = controller
        controller.show()
    }

    private func show(_ note: NoteConfig) {
        guard noteControllers[note.id] == nil else { return }

        let controller = DesktopNoteController(
            config: note,
            manager: self
        )
        noteControllers[note.id] = controller
        controller.show()
    }

    private func show(_ checklist: ChecklistConfig) {
        guard checklistControllers[checklist.id] == nil else { return }

        let controller = DesktopChecklistController(
            config: checklist,
            manager: self
        )
        checklistControllers[checklist.id] = controller
        controller.show()
    }

    private func show(_ launcher: LauncherConfig) {
        guard launcherControllers[launcher.id] == nil else { return }

        let controller = DesktopLauncherController(
            config: launcher,
            manager: self
        )
        launcherControllers[launcher.id] = controller
        controller.show()
    }

    private func loadZones() -> [ZoneConfig] {
        guard let data = UserDefaults.standard.data(forKey: zonesKey),
              let decoded = try? JSONDecoder().decode([ZoneConfig].self, from: data) else {
            return []
        }
        return decoded
    }

    private func saveZones() {
        guard let data = try? JSONEncoder().encode(zones) else { return }
        UserDefaults.standard.set(data, forKey: zonesKey)
    }

    private func loadNotes() -> [NoteConfig] {
        guard let data = UserDefaults.standard.data(forKey: notesKey),
              let decoded = try? JSONDecoder().decode(
                  [NoteConfig].self,
                  from: data
              ) else {
            return []
        }
        return decoded
    }

    private func saveNotes() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: notesKey)
    }

    private func loadChecklists() -> [ChecklistConfig] {
        guard let data = UserDefaults.standard.data(forKey: checklistsKey),
              let decoded = try? JSONDecoder().decode(
                  [ChecklistConfig].self,
                  from: data
              ) else {
            return []
        }
        return decoded
    }

    private func saveChecklists() {
        guard let data = try? JSONEncoder().encode(checklists) else {
            return
        }
        UserDefaults.standard.set(data, forKey: checklistsKey)
    }

    private func loadLaunchers() -> [LauncherConfig] {
        guard let data = UserDefaults.standard.data(forKey: launchersKey),
              let decoded = try? JSONDecoder().decode(
                  [LauncherConfig].self,
                  from: data
              ) else {
            return []
        }
        return decoded
    }

    private func saveLaunchers() {
        guard let data = try? JSONEncoder().encode(launchers) else {
            return
        }
        UserDefaults.standard.set(data, forKey: launchersKey)
    }

    private func makeInitialZones() -> [ZoneConfig] {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 360
        let height: CGFloat = 210
        let gap: CGFloat = 18
        let margin: CGFloat = 36
        let top = screen.maxY - margin

        let names = ["正在处理", "项目资料", "临时文件"]

        return names.enumerated().map { index, name in
            ZoneConfig(
                id: UUID(),
                name: name,
                x: screen.minX + margin + CGFloat(index) * (width + gap),
                y: top - height,
                width: width,
                height: height,
                collapsed: false
            )
        }
    }

    private func nextLauncherFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 320
        let height: CGFloat = 260
        let offset = CGFloat(launchers.count % 8) * 28

        let x = max(
            screen.minX + 30,
            min(
                screen.maxX - width - 30,
                screen.midX - width / 2 + offset
            )
        )
        let y = max(
            screen.minY + 30,
            screen.midY - height / 2 - offset
        )

        return NSRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }

    private func nextChecklistFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 320
        let height: CGFloat = 310
        let offset = CGFloat(checklists.count % 8) * 26

        let x = max(
            screen.minX + 30,
            min(
                screen.maxX - width - 30,
                screen.midX - width / 2 + offset
            )
        )
        let y = max(
            screen.minY + 30,
            screen.midY - height / 2 - offset
        )

        return NSRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }

    private func nextNoteFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 300
        let height: CGFloat = 250
        let offset = CGFloat(notes.count % 8) * 24

        let x = min(
            screen.maxX - width - 30,
            screen.midX - width / 2 + offset
        )
        let y = max(
            screen.minY + 30,
            screen.midY - height / 2 - offset
        )

        return NSRect(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }

    private func nextFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 360
        let height: CGFloat = 210
        let gap: CGFloat = 18
        let margin: CGFloat = 36

        let columns = max(1, Int((screen.width - margin * 2 + gap) / (width + gap)))
        let index = zones.count
        let col = index % columns
        let row = index / columns

        let x = screen.minX + margin + CGFloat(col) * (width + gap)
        let y = max(
            screen.minY + margin,
            screen.maxY - margin - height - CGFloat(row) * (height + gap)
        )

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func ensureZoneFolders() {
        for zone in zones {
            createFolderIfNeeded(for: zone)
        }
    }

    private func createFolderIfNeeded(for zone: ZoneConfig) {
        let url = folderURL(for: zone)

        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } catch {
            NSLog("DeskBox zone folder create failed: \(error)")
        }
    }

    private func migrateLegacyReferences() {
        for zone in zones {
            let key = ZoneStore.legacyFilesKey(for: zone.id)
            guard let paths = UserDefaults.standard.stringArray(forKey: key), !paths.isEmpty else {
                continue
            }

            let destinationFolder = folderURL(for: zone)
            var failedPaths: [String] = []

            for path in paths {
                let source = URL(fileURLWithPath: path).standardizedFileURL

                guard FileManager.default.fileExists(atPath: source.path) else {
                    continue
                }

                if source.deletingLastPathComponent().standardizedFileURL == destinationFolder.standardizedFileURL {
                    continue
                }

                let destination = ZoneStore.uniqueDestination(
                    in: destinationFolder,
                    preferredName: source.lastPathComponent
                )

                do {
                    try FileManager.default.moveItem(at: source, to: destination)
                } catch {
                    NSLog("DeskBox legacy migration failed: \(error)")
                    failedPaths.append(path)
                }
            }

            if failedPaths.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(failedPaths, forKey: key)
            }
        }
    }

    private func moveURLsToDesktop(_ urls: [URL]) -> Bool {
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            return false
        }

        var allSucceeded = true

        for source in urls {
            let destination = ZoneStore.uniqueDestination(
                in: desktop,
                preferredName: source.lastPathComponent
            )

            do {
                try FileManager.default.moveItem(at: source, to: destination)
            } catch {
                NSLog("DeskBox move to Desktop failed: \(error)")
                allSucceeded = false
            }
        }

        return allSucceeded
    }

    private func folderURL(for zone: ZoneConfig) -> URL {
        storageRoot.appendingPathComponent(safeFolderName(zone.name), isDirectory: true)
    }

    private func safeFolderName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
        let parts = name.components(separatedBy: invalid)
        let joined = parts.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "未命名分区" : joined
    }

    private func uniqueZoneName(base: String) -> String {
        if !zones.contains(where: { $0.name == base }) {
            return base
        }

        var index = 2
        while zones.contains(where: { $0.name == "\(base) \(index)" }) {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}
