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

struct LayoutItemSnapshot: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var collapsed: Bool
}

struct WorkspaceLayoutSnapshot: Codable, Equatable {
    var zones: [String: LayoutItemSnapshot]
    var notes: [String: LayoutItemSnapshot]
    var checklists: [String: LayoutItemSnapshot]
    var launchers: [String: LayoutItemSnapshot]
}

struct FileMoveRecord: Codable, Equatable {
    var sourcePath: String
    var destinationPath: String
    var fileNumber: UInt64?
}

struct FileMoveTransaction: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    var summary: String
    var items: [FileMoveRecord]
    var isUndone: Bool?

    var undoneValue: Bool {
        isUndone ?? false
    }
}

struct DeskBoxConfigurationBackup: Codable {
    let schemaVersion: Int
    let createdAt: Date
    let appVersion: String

    var workspaces: [WorkspaceConfig]
    var currentWorkspaceID: UUID

    var zones: [ZoneConfig]
    var notes: [NoteConfig]
    var checklists: [ChecklistConfig]
    var launchers: [LauncherConfig]

    var zoneWorkspace: [String: String]
    var noteWorkspace: [String: String]
    var checklistWorkspace: [String: String]
    var launcherWorkspace: [String: String]

    var lockedWorkspaceIDs: [String]
    var layoutSnapshots: [String: WorkspaceLayoutSnapshot]
    var showWorkspaceAtLaunch: Bool
}

enum DeskBoxConfigurationBackupError: LocalizedError {
    case unsupportedVersion(Int)
    case emptyWorkspaces
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "这个备份来自不兼容的配置版本（\(version)）。"
        case .emptyWorkspaces:
            return "备份中没有有效的工作区。"
        case .invalidData:
            return "这个文件不是有效的 DeskBox 配置备份。"
        }
    }
}

@MainActor
final class WorkspaceState: ObservableObject {
    @Published var workspaces: [WorkspaceConfig] = []
    @Published var currentID = UUID()
    @Published var isCurrentLayoutLocked = false
    @Published var currentHasLayoutSnapshot = false
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
    private let lockedWorkspacesKey = "DeskBox.LockedWorkspaces.v1"
    private let layoutSnapshotsKey = "DeskBox.LayoutSnapshots.v1"
    private let fileMoveHistoryKey = "DeskBox.FileMoveHistory.v1"

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
    private var lockedWorkspaceIDs: Set<String> = []
    private var layoutSnapshots: [String: WorkspaceLayoutSnapshot] = [:]
    private var fileMoveHistory: [FileMoveTransaction] = []

    private var startupRecoveryMessages: [String] = []
    private var zonesConfigurationWasMissing = false
    private var zonesConfigurationRecovered = false
    private var notesConfigurationRecovered = false
    private var checklistsConfigurationRecovered = false
    private var launchersConfigurationRecovered = false

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
        lockedWorkspaceIDs = loadLockedWorkspaceIDs()
        layoutSnapshots = loadLayoutSnapshots()
        fileMoveHistory = loadFileMoveHistory()

        zones = loadZones()
        notes = loadNotes()
        checklists = loadChecklists()
        launchers = loadLaunchers()

        let createdInitialZones: Bool
        if zones.isEmpty && zonesConfigurationWasMissing {
            zones = makeInitialZones()
            saveZones()
            createdInitialZones = true
        } else {
            createdInitialZones = false
        }

        if zonesConfigurationRecovered {
            saveZones()
        }
        if notesConfigurationRecovered {
            saveNotes()
        }
        if checklistsConfigurationRecovered {
            saveChecklists()
        }
        if launchersConfigurationRecovered {
            saveLaunchers()
        }

        ensureWorkspaceAssignments()
        syncWorkspaceState()

        if createdInitialZones {
            ensureZoneFolders()
        }

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

    var isCurrentWorkspaceLayoutLocked: Bool {
        lockedWorkspaceIDs.contains(currentWorkspaceID.uuidString)
    }

    var currentWorkspaceHasLayoutSnapshot: Bool {
        layoutSnapshots[currentWorkspaceID.uuidString] != nil
    }

    func toggleCurrentWorkspaceLayoutLock() {
        let key = currentWorkspaceID.uuidString

        if lockedWorkspaceIDs.contains(key) {
            lockedWorkspaceIDs.remove(key)
        } else {
            lockedWorkspaceIDs.insert(key)
        }

        saveLockedWorkspaceIDs()
        syncWorkspaceState()
        applyCurrentWorkspaceLayoutLock()
    }

    func saveCurrentWorkspaceLayoutSnapshot() {
        let workspaceID = currentWorkspaceID.uuidString

        let zoneSnapshots: [String: LayoutItemSnapshot] = Dictionary(
            uniqueKeysWithValues: zones.compactMap { zone in
                guard zoneWorkspace[zone.id.uuidString] == workspaceID else {
                    return nil
                }
                return (
                    zone.id.uuidString,
                    LayoutItemSnapshot(
                        x: zone.x,
                        y: zone.y,
                        width: zone.width,
                        height: zone.height,
                        collapsed: zone.collapsed
                    )
                )
            }
        )

        let noteSnapshots: [String: LayoutItemSnapshot] = Dictionary(
            uniqueKeysWithValues: notes.compactMap { note in
                guard noteWorkspace[note.id.uuidString] == workspaceID else {
                    return nil
                }
                return (
                    note.id.uuidString,
                    LayoutItemSnapshot(
                        x: note.x,
                        y: note.y,
                        width: note.width,
                        height: note.height,
                        collapsed: note.collapsedValue
                    )
                )
            }
        )

        let checklistSnapshots: [String: LayoutItemSnapshot] = Dictionary(
            uniqueKeysWithValues: checklists.compactMap { checklist in
                guard checklistWorkspace[checklist.id.uuidString]
                        == workspaceID else {
                    return nil
                }
                return (
                    checklist.id.uuidString,
                    LayoutItemSnapshot(
                        x: checklist.x,
                        y: checklist.y,
                        width: checklist.width,
                        height: checklist.height,
                        collapsed: checklist.collapsedValue
                    )
                )
            }
        )

        let launcherSnapshots: [String: LayoutItemSnapshot] = Dictionary(
            uniqueKeysWithValues: launchers.compactMap { launcher in
                guard launcherWorkspace[launcher.id.uuidString]
                        == workspaceID else {
                    return nil
                }
                return (
                    launcher.id.uuidString,
                    LayoutItemSnapshot(
                        x: launcher.x,
                        y: launcher.y,
                        width: launcher.width,
                        height: launcher.height,
                        collapsed: launcher.collapsedValue
                    )
                )
            }
        )

        layoutSnapshots[workspaceID] = WorkspaceLayoutSnapshot(
            zones: zoneSnapshots,
            notes: noteSnapshots,
            checklists: checklistSnapshots,
            launchers: launcherSnapshots
        )

        saveLayoutSnapshots()
        syncWorkspaceState()
    }

    func restoreCurrentWorkspaceLayoutSnapshot() {
        let workspaceID = currentWorkspaceID.uuidString
        guard let snapshot = layoutSnapshots[workspaceID] else {
            NSSound.beep()
            return
        }

        for index in zones.indices {
            let id = zones[index].id.uuidString
            guard zoneWorkspace[id] == workspaceID,
                  let saved = snapshot.zones[id] else {
                continue
            }

            zones[index].x = saved.x
            zones[index].y = saved.y
            zones[index].width = saved.width
            zones[index].height = saved.height
            zones[index].collapsed = saved.collapsed
        }

        for index in notes.indices {
            let id = notes[index].id.uuidString
            guard noteWorkspace[id] == workspaceID,
                  let saved = snapshot.notes[id] else {
                continue
            }

            notes[index].x = saved.x
            notes[index].y = saved.y
            notes[index].width = saved.width
            notes[index].height = saved.height
            notes[index].collapsedValue = saved.collapsed
        }

        for index in checklists.indices {
            let id = checklists[index].id.uuidString
            guard checklistWorkspace[id] == workspaceID,
                  let saved = snapshot.checklists[id] else {
                continue
            }

            checklists[index].x = saved.x
            checklists[index].y = saved.y
            checklists[index].width = saved.width
            checklists[index].height = saved.height
            checklists[index].collapsedValue = saved.collapsed
        }

        for index in launchers.indices {
            let id = launchers[index].id.uuidString
            guard launcherWorkspace[id] == workspaceID,
                  let saved = snapshot.launchers[id] else {
                continue
            }

            launchers[index].x = saved.x
            launchers[index].y = saved.y
            launchers[index].width = saved.width
            launchers[index].height = saved.height
            launchers[index].collapsedValue = saved.collapsed
        }

        saveZones()
        saveNotes()
        saveChecklists()
        saveLaunchers()

        rebuildCurrentWorkspaceControllers()
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

    var storageFolderURL: URL {
        storageRoot
    }

    func openStorageFolder() {
        NSWorkspace.shared.open(storageRoot)
    }

    func configurationBackupData() throws -> Data {
        let backup = DeskBoxConfigurationBackup(
            schemaVersion: 1,
            createdAt: Date(),
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.1.0",
            workspaces: workspaces,
            currentWorkspaceID: currentWorkspaceID,
            zones: zones,
            notes: notes,
            checklists: checklists,
            launchers: launchers,
            zoneWorkspace: zoneWorkspace,
            noteWorkspace: noteWorkspace,
            checklistWorkspace: checklistWorkspace,
            launcherWorkspace: launcherWorkspace,
            lockedWorkspaceIDs: Array(lockedWorkspaceIDs),
            layoutSnapshots: layoutSnapshots,
            showWorkspaceAtLaunch:
                DeskBoxPreferences.showWorkspaceAtLaunch
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    func restoreConfigurationBackup(
        from data: Data
    ) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let backup: DeskBoxConfigurationBackup
        do {
            backup = try decoder.decode(
                DeskBoxConfigurationBackup.self,
                from: data
            )
        } catch {
            throw DeskBoxConfigurationBackupError.invalidData
        }

        guard backup.schemaVersion == 1 else {
            throw DeskBoxConfigurationBackupError
                .unsupportedVersion(backup.schemaVersion)
        }

        guard !backup.workspaces.isEmpty else {
            throw DeskBoxConfigurationBackupError.emptyWorkspaces
        }

        try writeAutomaticConfigurationBackup()

        let restoredWorkspaceIDs = Set(
            backup.workspaces.map { $0.id.uuidString }
        )

        let restoredCurrentWorkspaceID:
            UUID = restoredWorkspaceIDs.contains(
                backup.currentWorkspaceID.uuidString
            )
            ? backup.currentWorkspaceID
            : backup.workspaces[0].id

        let importedZoneIDs = Set(
            backup.zones.map { $0.id }
        )
        let importedFolderNames = Set(
            backup.zones.map {
                safeFolderName($0.name).lowercased()
            }
        )

        let preservedZones = zones.filter { zone in
            !importedZoneIDs.contains(zone.id)
                && !importedFolderNames.contains(
                    safeFolderName(zone.name).lowercased()
                )
        }

        let restoredZones =
            backup.zones + preservedZones

        var restoredZoneWorkspace =
            backup.zoneWorkspace

        for zone in preservedZones {
            restoredZoneWorkspace[zone.id.uuidString] =
                restoredCurrentWorkspaceID.uuidString
        }

        func validMap(
            _ map: [String: String],
            validComponentIDs: Set<String>
        ) -> [String: String] {
            map.filter { key, value in
                validComponentIDs.contains(key)
                    && restoredWorkspaceIDs.contains(value)
            }
        }

        let restoredNoteWorkspace = validMap(
            backup.noteWorkspace,
            validComponentIDs: Set(
                backup.notes.map { $0.id.uuidString }
            )
        )
        let restoredChecklistWorkspace = validMap(
            backup.checklistWorkspace,
            validComponentIDs: Set(
                backup.checklists.map {
                    $0.id.uuidString
                }
            )
        )
        let restoredLauncherWorkspace = validMap(
            backup.launcherWorkspace,
            validComponentIDs: Set(
                backup.launchers.map {
                    $0.id.uuidString
                }
            )
        )

        restoredZoneWorkspace = validMap(
            restoredZoneWorkspace,
            validComponentIDs: Set(
                restoredZones.map { $0.id.uuidString }
            )
        )

        closeAllControllersForConfigurationRestore()

        workspaces = backup.workspaces
        currentWorkspaceID = restoredCurrentWorkspaceID

        zones = restoredZones
        notes = backup.notes
        checklists = backup.checklists
        launchers = backup.launchers

        zoneWorkspace = restoredZoneWorkspace
        noteWorkspace = restoredNoteWorkspace
        checklistWorkspace =
            restoredChecklistWorkspace
        launcherWorkspace = restoredLauncherWorkspace

        lockedWorkspaceIDs = Set(
            backup.lockedWorkspaceIDs.filter {
                restoredWorkspaceIDs.contains($0)
            }
        )

        layoutSnapshots =
            backup.layoutSnapshots.filter {
                restoredWorkspaceIDs.contains($0.key)
            }

        DeskBoxPreferences.showWorkspaceAtLaunch =
            backup.showWorkspaceAtLaunch

        ensureWorkspaceAssignments()

        saveWorkspaces()
        saveCurrentWorkspaceID()
        saveZones()
        saveNotes()
        saveChecklists()
        saveLaunchers()
        saveWorkspaceAssignments()
        saveLockedWorkspaceIDs()
        saveLayoutSnapshots()

        ensureZoneFolders()
        selectionState.clear()
        syncWorkspaceState()

        if !areZonesHidden {
            applyCurrentWorkspaceVisibility()
        }
    }

    private func closeAllControllersForConfigurationRestore() {
        for controller in controllers.values {
            controller.close()
        }
        for controller in noteControllers.values {
            controller.close()
        }
        for controller in checklistControllers.values {
            controller.close()
        }
        for controller in launcherControllers.values {
            controller.close()
        }

        controllers.removeAll()
        noteControllers.removeAll()
        checklistControllers.removeAll()
        launcherControllers.removeAll()
    }

    private func writeAutomaticConfigurationBackup() throws {
        let data = try configurationBackupData()

        let applicationSupport =
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!

        let directory = applicationSupport
            .appendingPathComponent(
                "DeskBox",
                isDirectory: true
            )
            .appendingPathComponent(
                "Backups",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let url = directory.appendingPathComponent(
            "DeskBox-AutoBackup-\(formatter.string(from: Date())).json"
        )

        try data.write(
            to: url,
            options: .atomic
        )

        let backups = (
            try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles]
            )
        ) ?? []

        let sorted = backups.sorted { lhs, rhs in
            let l = (
                try? lhs.resourceValues(
                    forKeys: [
                        .contentModificationDateKey
                    ]
                ).contentModificationDate
            ) ?? .distantPast

            let r = (
                try? rhs.resourceValues(
                    forKeys: [
                        .contentModificationDateKey
                    ]
                ).contentModificationDate
            ) ?? .distantPast

            return l > r
        }

        for oldBackup in sorted.dropFirst(10) {
            try? FileManager.default.removeItem(
                at: oldBackup
            )
        }
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
        lockedWorkspaceIDs.remove(current.id.uuidString)
        layoutSnapshots.removeValue(forKey: current.id.uuidString)
        currentWorkspaceID = target.id

        saveWorkspaces()
        saveCurrentWorkspaceID()
        saveWorkspaceAssignments()
        saveLockedWorkspaceIDs()
        saveLayoutSnapshots()
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

        var oldIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: oldURL.path,
            isDirectory: &oldIsDirectory
        ),
        oldIsDirectory.boolValue else {
            showError(
                "无法重命名",
                "这个分区对应的文件夹不存在，可能已在 Finder 中被改名或移动。请先恢复原文件夹，再重试。"
            )
            controllers[id]?.store.reload()
            return
        }

        var updated = zones[index]
        updated.name = name
        let newURL = folderURL(for: updated)

        if oldURL.standardizedFileURL != newURL.standardizedFileURL {
            if FileManager.default.fileExists(atPath: newURL.path) {
                showError("无法重命名", "目标文件夹已经存在：\(newURL.lastPathComponent)")
                return
            }

            do {
                try FileManager.default.moveItem(
                    at: oldURL,
                    to: newURL
                )
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

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: folder.path,
            isDirectory: &isDirectory
        ),
        isDirectory.boolValue else {
            showError(
                "无法删除分区",
                "这个分区对应的文件夹不存在，可能已在 Finder 中被改名或移动。为避免误删配置，DeskBox 已停止操作。"
            )
            controllers[id]?.store.reload()
            return
        }

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
            guard let desktop = FileManager.default.urls(
                for: .desktopDirectory,
                in: .userDomainMask
            ).first else {
                showError(
                    "删除分区失败",
                    "DeskBox 无法访问桌面文件夹。"
                )
                return
            }

            guard performFileMove(
                contents,
                to: desktop,
                summary: "删除“\(zone.name)”前移回桌面"
            ) else {
                showError(
                    "删除分区失败",
                    "有文件未能移回桌面，分区没有被删除。"
                )
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
        guard let zone = zones.first(
            where: { $0.id == destinationID }
        ) else {
            return
        }

        let destinationFolder = folderURL(for: zone)
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(
            atPath: destinationFolder.path,
            isDirectory: &isDirectory
        ),
        isDirectory.boolValue else {
            showError(
                "分区文件夹不存在",
                "“\(zone.name)”对应的文件夹可能已在 Finder 中被改名或移动。DeskBox 没有移动任何文件。"
            )
            controllers[destinationID]?.store.reload()
            return
        }

        let result = performFileMove(
            urls,
            to: destinationFolder,
            summary: "移动到“\(zone.name)”"
        )

        refreshAllZoneStores()
        selectionState.clear()
        controllers[destinationID]?.focusAfterFileOperation()

        if !result {
            showError(
                "有文件未能移动",
                "请检查文件是否正在被其他程序占用，或是否有访问权限。"
            )
        }
    }

    func moveFilesToDesktop(_ urls: [URL]) {
        guard let desktop = FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first else {
            showError("无法访问桌面", "DeskBox 无法找到桌面文件夹。")
            return
        }

        let result = performFileMove(
            urls,
            to: desktop,
            summary: "移回桌面"
        )

        refreshAllZoneStores()
        selectionState.clear()

        if !result {
            showError(
                "有文件未能移回桌面",
                "请检查文件是否正在被其他程序占用，或是否有访问权限。"
            )
        }
    }

    var canUndoLastFileMove: Bool {
        latestUndoableFileMoveIndex != nil
    }

    var undoFileMoveMenuTitle: String {
        guard let index = latestUndoableFileMoveIndex else {
            return "撤销文件移动"
        }

        let transaction = fileMoveHistory[index]
        let count = transaction.items.count
        return count > 1
            ? "撤销：\(transaction.summary)（\(count) 项）"
            : "撤销：\(transaction.summary)"
    }

    var latestUndoableFileMoveID: UUID? {
        guard let index = latestUndoableFileMoveIndex else {
            return nil
        }
        return fileMoveHistory[index].id
    }

    func recentFileMoveTransactions() -> [FileMoveTransaction] {
        Array(fileMoveHistory.reversed())
    }

    private var latestUndoableFileMoveIndex: Int? {
        fileMoveHistory.lastIndex(where: { !$0.undoneValue })
    }

    func undoLastFileMove() {
        guard let transactionIndex = latestUndoableFileMoveIndex else {
            NSSound.beep()
            return
        }

        let transaction = fileMoveHistory[transactionIndex]

        var failed: [FileMoveRecord] = []
        var restoredCount = 0

        for item in transaction.items.reversed() {
            let currentURL = URL(
                fileURLWithPath: item.destinationPath
            ).standardizedFileURL

            guard FileManager.default.fileExists(
                atPath: currentURL.path
            ),
            matchesRecordedFile(
                currentURL,
                fileNumber: item.fileNumber
            ) else {
                failed.append(item)
                continue
            }

            let originalURL = URL(
                fileURLWithPath: item.sourcePath
            ).standardizedFileURL
            let originalFolder =
                originalURL.deletingLastPathComponent()

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: originalFolder.path,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue else {
                failed.append(item)
                continue
            }

            let destination = ZoneStore.uniqueDestination(
                in: originalFolder,
                preferredName: originalURL.lastPathComponent
            )

            do {
                try FileManager.default.moveItem(
                    at: currentURL,
                    to: destination
                )
                restoredCount += 1
            } catch {
                NSLog("DeskBox undo file move failed: \(error)")
                failed.append(item)
            }
        }

        if failed.isEmpty {
            fileMoveHistory[transactionIndex].isUndone = true
        }

        saveFileMoveHistory()
        refreshAllZoneStores()
        selectionState.clear()

        if !failed.isEmpty {
            showError(
                "部分文件未能撤销",
                "已恢复 \(restoredCount) 项，还有 \(failed.count) 项无法恢复。DeskBox 没有覆盖任何现有文件，可稍后再次尝试。"
            )
        }
    }

    private func performFileMove(
        _ urls: [URL],
        to destinationFolder: URL,
        summary: String
    ) -> Bool {
        var allSucceeded = true
        var records: [FileMoveRecord] = []

        for sourceURL in urls {
            let source = sourceURL.standardizedFileURL

            guard FileManager.default.fileExists(
                atPath: source.path
            ) else {
                allSucceeded = false
                continue
            }

            if source.deletingLastPathComponent()
                .standardizedFileURL == destinationFolder.standardizedFileURL {
                continue
            }

            let destination = ZoneStore.uniqueDestination(
                in: destinationFolder,
                preferredName: source.lastPathComponent
            )

            do {
                try FileManager.default.moveItem(
                    at: source,
                    to: destination
                )

                records.append(
                    FileMoveRecord(
                        sourcePath: source.path,
                        destinationPath: destination.path,
                        fileNumber: fileNumber(for: destination)
                    )
                )
            } catch {
                NSLog("DeskBox file move failed: \(error)")
                allSucceeded = false
            }
        }

        if !records.isEmpty {
            appendFileMoveHistory(
                summary: summary,
                records: records
            )
        }

        return allSucceeded
    }

    private func fileNumber(for url: URL) -> UInt64? {
        guard let attributes = try? FileManager.default
            .attributesOfItem(atPath: url.path),
              let value = attributes[.systemFileNumber]
                as? NSNumber else {
            return nil
        }

        return value.uint64Value
    }

    private func matchesRecordedFile(
        _ url: URL,
        fileNumber: UInt64?
    ) -> Bool {
        guard let fileNumber else {
            return true
        }

        return self.fileNumber(for: url) == fileNumber
    }

    private func appendFileMoveHistory(
        summary: String,
        records: [FileMoveRecord]
    ) {
        fileMoveHistory.append(
            FileMoveTransaction(
                id: UUID(),
                date: Date(),
                summary: summary,
                items: records,
                isUndone: false
            )
        )

        if fileMoveHistory.count > 50 {
            fileMoveHistory.removeFirst(
                fileMoveHistory.count - 50
            )
        }

        saveFileMoveHistory()
    }

    private func refreshAllZoneStores() {
        for (_, controller) in controllers {
            controller.store.reload()
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

        applyCurrentWorkspaceLayoutLock()
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
        workspaceState.isCurrentLayoutLocked =
            isCurrentWorkspaceLayoutLocked
        workspaceState.currentHasLayoutSnapshot =
            currentWorkspaceHasLayoutSnapshot
    }

    private func applyCurrentWorkspaceLayoutLock() {
        let locked = isCurrentWorkspaceLayoutLocked

        for zone in zones where isInCurrentWorkspace(
            zone.id,
            map: zoneWorkspace
        ) {
            controllers[zone.id]?.setLayoutLocked(locked)
        }

        for note in notes where isInCurrentWorkspace(
            note.id,
            map: noteWorkspace
        ) {
            noteControllers[note.id]?.setLayoutLocked(locked)
        }

        for checklist in checklists where isInCurrentWorkspace(
            checklist.id,
            map: checklistWorkspace
        ) {
            checklistControllers[checklist.id]?.setLayoutLocked(locked)
        }

        for launcher in launchers where isInCurrentWorkspace(
            launcher.id,
            map: launcherWorkspace
        ) {
            launcherControllers[launcher.id]?.setLayoutLocked(locked)
        }
    }

    private func rebuildCurrentWorkspaceControllers() {
        let workspaceID = currentWorkspaceID.uuidString

        for zone in zones
            where zoneWorkspace[zone.id.uuidString] == workspaceID {
            controllers[zone.id]?.close()
            controllers[zone.id] = nil
        }

        for note in notes
            where noteWorkspace[note.id.uuidString] == workspaceID {
            noteControllers[note.id]?.close()
            noteControllers[note.id] = nil
        }

        for checklist in checklists
            where checklistWorkspace[checklist.id.uuidString] == workspaceID {
            checklistControllers[checklist.id]?.close()
            checklistControllers[checklist.id] = nil
        }

        for launcher in launchers
            where launcherWorkspace[launcher.id.uuidString] == workspaceID {
            launcherControllers[launcher.id]?.close()
            launcherControllers[launcher.id] = nil
        }

        if !areZonesHidden {
            applyCurrentWorkspaceVisibility()
        }
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
        guard let data = UserDefaults.standard.data(
            forKey: workspacesKey
        ) else {
            return []
        }

        do {
            return try JSONDecoder().decode(
                [WorkspaceConfig].self,
                from: data
            )
        } catch {
            archiveCorruptConfiguration(
                data,
                key: workspacesKey,
                label: "工作区"
            )
            startupRecoveryMessages.append(
                "工作区配置损坏，已创建一个新的默认工作区。"
            )
            return []
        }
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
        guard let data = UserDefaults.standard.data(
            forKey: key
        ) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode(
                [String: String].self,
                from: data
            )
        } catch {
            archiveCorruptConfiguration(
                data,
                key: key,
                label: "工作区关联"
            )
            startupRecoveryMessages.append(
                "部分工作区关联配置损坏，DeskBox 已重新整理组件归属。"
            )
            return [:]
        }
    }

    private func loadLockedWorkspaceIDs() -> Set<String> {
        let values = UserDefaults.standard.stringArray(
            forKey: lockedWorkspacesKey
        ) ?? []
        return Set(values)
    }

    private func saveLockedWorkspaceIDs() {
        UserDefaults.standard.set(
            Array(lockedWorkspaceIDs),
            forKey: lockedWorkspacesKey
        )
    }

    private func loadLayoutSnapshots()
        -> [String: WorkspaceLayoutSnapshot] {
        guard let data = UserDefaults.standard.data(
            forKey: layoutSnapshotsKey
        ) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode(
                [String: WorkspaceLayoutSnapshot].self,
                from: data
            )
        } catch {
            archiveCorruptConfiguration(
                data,
                key: layoutSnapshotsKey,
                label: "布局快照"
            )
            UserDefaults.standard.removeObject(
                forKey: layoutSnapshotsKey
            )
            startupRecoveryMessages.append(
                "布局快照损坏，已清除损坏快照；当前组件位置不会被删除。"
            )
            return [:]
        }
    }

    private func saveLayoutSnapshots() {
        guard let data = try? JSONEncoder().encode(layoutSnapshots) else {
            return
        }
        UserDefaults.standard.set(data, forKey: layoutSnapshotsKey)
    }

    private func loadFileMoveHistory() -> [FileMoveTransaction] {
        guard let data = UserDefaults.standard.data(
            forKey: fileMoveHistoryKey
        ) else {
            return []
        }

        do {
            return try JSONDecoder().decode(
                [FileMoveTransaction].self,
                from: data
            )
        } catch {
            archiveCorruptConfiguration(
                data,
                key: fileMoveHistoryKey,
                label: "最近操作"
            )
            UserDefaults.standard.removeObject(
                forKey: fileMoveHistoryKey
            )
            startupRecoveryMessages.append(
                "最近操作记录损坏，已保留损坏副本并重置操作历史。"
            )
            return []
        }
    }

    private func saveFileMoveHistory() {
        guard let data = try? JSONEncoder().encode(
            fileMoveHistory
        ) else {
            return
        }

        UserDefaults.standard.set(
            data,
            forKey: fileMoveHistoryKey
        )
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
        controller.setLayoutLocked(isCurrentWorkspaceLayoutLocked)
    }

    private func show(_ note: NoteConfig) {
        guard noteControllers[note.id] == nil else { return }

        let controller = DesktopNoteController(
            config: note,
            manager: self
        )
        noteControllers[note.id] = controller
        controller.show()
        controller.setLayoutLocked(isCurrentWorkspaceLayoutLocked)
    }

    private func show(_ checklist: ChecklistConfig) {
        guard checklistControllers[checklist.id] == nil else { return }

        let controller = DesktopChecklistController(
            config: checklist,
            manager: self
        )
        checklistControllers[checklist.id] = controller
        controller.show()
        controller.setLayoutLocked(isCurrentWorkspaceLayoutLocked)
    }

    private func show(_ launcher: LauncherConfig) {
        guard launcherControllers[launcher.id] == nil else { return }

        let controller = DesktopLauncherController(
            config: launcher,
            manager: self
        )
        launcherControllers[launcher.id] = controller
        controller.show()
        controller.setLayoutLocked(isCurrentWorkspaceLayoutLocked)
    }

    private func loadZones() -> [ZoneConfig] {
        guard let data = UserDefaults.standard.data(
            forKey: zonesKey
        ) else {
            zonesConfigurationWasMissing = true
            return []
        }

        do {
            return try JSONDecoder().decode(
                [ZoneConfig].self,
                from: data
            )
        } catch {
            archiveCorruptConfiguration(
                data,
                key: zonesKey,
                label: "文件分区"
            )

            zonesConfigurationRecovered = true
            let recovered = recoverZonesFromStorageDirectories()

            if recovered.isEmpty {
                startupRecoveryMessages.append(
                    "文件分区配置损坏。DeskBox 没有创建新的空分区；真实文件目录保持原样。"
                )
            } else {
                startupRecoveryMessages.append(
                    "文件分区配置损坏，已根据真实文件夹恢复 \(recovered.count) 个分区入口。"
                )
            }

            return recovered
        }
    }

    private func saveZones() {
        guard let data = try? JSONEncoder().encode(zones) else { return }
        UserDefaults.standard.set(data, forKey: zonesKey)
    }

    private func loadNotes() -> [NoteConfig] {
        guard let data = UserDefaults.standard.data(
            forKey: notesKey
        ) else {
            return []
        }

        do {
            return try JSONDecoder().decode(
                [NoteConfig].self,
                from: data
            )
        } catch {
            archiveCorruptConfiguration(
                data,
                key: notesKey,
                label: "便签"
            )
            notesConfigurationRecovered = true
            startupRecoveryMessages.append(
                "便签配置损坏，已隔离损坏数据；文件分区不受影响。"
            )
            return []
        }
    }

    private func saveNotes() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: notesKey)
    }

    private func loadChecklists() -> [ChecklistConfig] {
        guard let data = UserDefaults.standard.data(
            forKey: checklistsKey
        ) else {
            return []
        }

        do {
            return try JSONDecoder().decode(
                [ChecklistConfig].self,
                from: data
            )
        } catch {
            archiveCorruptConfiguration(
                data,
                key: checklistsKey,
                label: "待办清单"
            )
            checklistsConfigurationRecovered = true
            startupRecoveryMessages.append(
                "待办配置损坏，已隔离损坏数据；真实文件不受影响。"
            )
            return []
        }
    }

    private func saveChecklists() {
        guard let data = try? JSONEncoder().encode(checklists) else {
            return
        }
        UserDefaults.standard.set(data, forKey: checklistsKey)
    }

    private func loadLaunchers() -> [LauncherConfig] {
        guard let data = UserDefaults.standard.data(
            forKey: launchersKey
        ) else {
            return []
        }

        do {
            return try JSONDecoder().decode(
                [LauncherConfig].self,
                from: data
            )
        } catch {
            archiveCorruptConfiguration(
                data,
                key: launchersKey,
                label: "快捷入口"
            )
            launchersConfigurationRecovered = true
            startupRecoveryMessages.append(
                "快捷入口配置损坏，已隔离损坏数据；原文件和应用不受影响。"
            )
            return []
        }
    }

    private func saveLaunchers() {
        guard let data = try? JSONEncoder().encode(launchers) else {
            return
        }
        UserDefaults.standard.set(data, forKey: launchersKey)
    }

    func createRecoverySnapshotAfterUncleanExit() {
        do {
            try writeAutomaticConfigurationBackup()
            NSLog(
                "DeskBox detected an unclean previous exit; recovery snapshot created."
            )
        } catch {
            NSLog(
                "DeskBox recovery snapshot after unclean exit failed: \(error)"
            )
        }
    }

    func presentStartupRecoveryIfNeeded() {
        guard !startupRecoveryMessages.isEmpty else {
            return
        }

        var seen = Set<String>()
        let uniqueMessages = startupRecoveryMessages.filter {
            seen.insert($0).inserted
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "DeskBox 已恢复部分配置"
        alert.informativeText = (
            uniqueMessages.map { "• \($0)" }
                .joined(separator: "\\n")
            + "\\n\\n损坏的原始配置已保存在："
            + "\\n~/Library/Application Support/DeskBox/Recovery/"
            + "\\n\\n真实文件没有被删除或覆盖。"
        )
        alert.addButton(withTitle: "知道了")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        startupRecoveryMessages.removeAll()
    }

    private func archiveCorruptConfiguration(
        _ data: Data,
        key: String,
        label: String
    ) {
        let fileManager = FileManager.default

        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            NSLog(
                "DeskBox could not locate Application Support for corrupt configuration archive."
            )
            return
        }

        let directory = applicationSupport
            .appendingPathComponent(
                "DeskBox",
                isDirectory: true
            )
            .appendingPathComponent(
                "Recovery",
                isDirectory: true
            )

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let formatter = DateFormatter()
            formatter.locale = Locale(
                identifier: "en_US_POSIX"
            )
            formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"

            let safeKey = key.replacingOccurrences(
                of: "[^A-Za-z0-9._-]",
                with: "-",
                options: .regularExpression
            )

            let url = directory.appendingPathComponent(
                "\(formatter.string(from: Date()))-\(safeKey).bin"
            )

            try data.write(
                to: url,
                options: .atomic
            )

            NSLog(
                "DeskBox archived corrupt \(label) configuration to \(url.path)"
            )
        } catch {
            NSLog(
                "DeskBox failed to archive corrupt \(label) configuration: \(error)"
            )
        }
    }

    private func recoverZonesFromStorageDirectories()
        -> [ZoneConfig] {
        let fileManager = FileManager.default

        let urls = (
            try? fileManager.contentsOfDirectory(
                at: storageRoot,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .nameKey
                ],
                options: [.skipsHiddenFiles]
            )
        ) ?? []

        let folders = urls.filter { url in
            (
                try? url.resourceValues(
                    forKeys: [.isDirectoryKey]
                ).isDirectory
            ) ?? false
        }
        .sorted {
            $0.lastPathComponent.localizedStandardCompare(
                $1.lastPathComponent
            ) == .orderedAscending
        }

        guard !folders.isEmpty else {
            return []
        }

        let screen = NSScreen.main?.visibleFrame
            ?? NSRect(
                x: 0,
                y: 0,
                width: 1440,
                height: 900
            )

        let width: CGFloat = 360
        let height: CGFloat = 210
        let gap: CGFloat = 18
        let margin: CGFloat = 36

        let usableWidth = max(
            width,
            screen.width - margin * 2
        )
        let columns = max(
            1,
            Int(
                (usableWidth + gap)
                / (width + gap)
            )
        )

        return folders.enumerated().map {
            index,
            folder in

            let column = index % columns
            let row = index / columns

            return ZoneConfig(
                id: UUID(),
                name: folder.lastPathComponent,
                x: screen.minX
                    + margin
                    + CGFloat(column) * (width + gap),
                y: screen.maxY
                    - margin
                    - height
                    - CGFloat(row) * (height + gap),
                width: width,
                height: height,
                collapsed: false
            )
        }
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
