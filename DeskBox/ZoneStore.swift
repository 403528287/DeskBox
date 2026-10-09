import Foundation
import AppKit

@MainActor
final class ZoneStore: ObservableObject {
    let zoneID: UUID

    @Published var name: String
    @Published var collapsed: Bool
    @Published var visualCollapsed: Bool
    @Published var contentOpacity: Double
    @Published var contentOffset: CGFloat
    @Published private(set) var files: [URL] = []
    @Published private(set) var isDirectoryMissing = false

    private(set) var directoryURL: URL

    init(zoneID: UUID, name: String, collapsed: Bool, directoryURL: URL) {
        self.zoneID = zoneID
        self.name = name
        self.collapsed = collapsed
        self.visualCollapsed = collapsed
        self.contentOpacity = collapsed ? 0 : 1
        self.contentOffset = collapsed ? -6 : 0
        self.directoryURL = directoryURL
        reload()
    }

    static func legacyFilesKey(for zoneID: UUID) -> String {
        "DeskBox.Zone.\(zoneID.uuidString).FilePaths"
    }

    private var orderKey: String {
        "DeskBox.Zone.\(zoneID.uuidString).Order"
    }

    func rename(to newName: String, directoryURL: URL) {
        name = newName
        self.directoryURL = directoryURL
        reload()
    }

    func reload() {
        let urls = currentDirectoryContents()
        files = urls
    }

    func reloadIfChanged() {
        let urls = currentDirectoryContents()
        let oldPaths = files.map { $0.standardizedFileURL.path }
        let newPaths = urls.map { $0.standardizedFileURL.path }

        if oldPaths != newPaths {
            files = urls
        }
    }

    private func currentDirectoryContents() -> [URL] {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: directoryURL.path,
            isDirectory: &isDirectory
        )

        guard exists, isDirectory.boolValue else {
            isDirectoryMissing = true
            return []
        }

        isDirectoryMissing = false

        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        let defaultSorted = urls.sorted { lhs, rhs in
            let lDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let rDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if lDir != rDir { return lDir && !rDir }
            return lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }

        let savedNames = UserDefaults.standard.stringArray(forKey: orderKey) ?? []
        guard !savedNames.isEmpty else {
            saveOrder(defaultSorted)
            return defaultSorted
        }

        let byName = Dictionary(
            uniqueKeysWithValues: defaultSorted.map { ($0.lastPathComponent, $0) }
        )

        var ordered: [URL] = savedNames.compactMap { byName[$0] }
        let alreadyIncluded = Set(ordered.map(\.lastPathComponent))

        ordered.append(
            contentsOf: defaultSorted.filter {
                !alreadyIncluded.contains($0.lastPathComponent)
            }
        )

        saveOrder(ordered)
        return ordered
    }

    func reorder(
        _ draggedURLs: [URL],
        relativeTo targetURL: URL,
        after: Bool
    ) {
        guard let reordered = reorderedFiles(
            draggedURLs,
            relativeTo: targetURL,
            after: after
        ) else {
            return
        }

        files = reordered
        saveOrder(reordered)
    }

    func previewReorder(
        _ draggedURLs: [URL],
        relativeTo targetURL: URL,
        after: Bool
    ) {
        guard let reordered = reorderedFiles(
            draggedURLs,
            relativeTo: targetURL,
            after: after
        ), reordered != files else {
            return
        }

        files = reordered
    }

    func reorderToEnd(_ draggedURLs: [URL]) {
        let draggedNames = Set(
            draggedURLs.map(\.lastPathComponent)
        )

        let moving = files.filter {
            draggedNames.contains($0.lastPathComponent)
        }
        guard !moving.isEmpty else { return }

        let remaining = files.filter {
            !draggedNames.contains($0.lastPathComponent)
        }

        let reordered = remaining + moving
        files = reordered
        saveOrder(reordered)
    }

    func commitCurrentOrder() {
        saveOrder(files)
    }

    func restoreSavedOrder() {
        reload()
    }

    private func reorderedFiles(
        _ draggedURLs: [URL],
        relativeTo targetURL: URL,
        after: Bool
    ) -> [URL]? {
        let draggedNames = Set(
            draggedURLs.map(\.lastPathComponent)
        )
        guard !draggedNames.contains(
            targetURL.lastPathComponent
        ) else {
            return nil
        }

        let moving = files.filter {
            draggedNames.contains($0.lastPathComponent)
        }
        guard !moving.isEmpty else { return nil }

        var remaining = files.filter {
            !draggedNames.contains($0.lastPathComponent)
        }

        guard let targetIndex = remaining.firstIndex(where: {
            $0.lastPathComponent == targetURL.lastPathComponent
        }) else {
            return nil
        }

        let insertionIndex = after
            ? min(targetIndex + 1, remaining.count)
            : targetIndex

        remaining.insert(
            contentsOf: moving,
            at: insertionIndex
        )
        return remaining
    }

    func reorder(
        fileNames: [String],
        relativeTo targetURL: URL,
        after: Bool
    ) {
        let movingNames = Set(fileNames)
        let moving = files.filter {
            movingNames.contains($0.lastPathComponent)
        }
        guard !moving.isEmpty else { return }

        var remaining = files.filter {
            !movingNames.contains($0.lastPathComponent)
        }

        guard let targetIndex = remaining.firstIndex(where: {
            $0.lastPathComponent == targetURL.lastPathComponent
        }) else {
            return
        }

        let insertionIndex = after
            ? min(targetIndex + 1, remaining.count)
            : targetIndex

        remaining.insert(
            contentsOf: moving,
            at: insertionIndex
        )
        files = remaining
        saveOrder(remaining)
    }

    private func saveOrder(_ urls: [URL]) {
        let names = urls.map(\.lastPathComponent)
        let existing = UserDefaults.standard.stringArray(forKey: orderKey) ?? []

        if existing != names {
            UserDefaults.standard.set(names, forKey: orderKey)
        }
    }

    @discardableResult
    func moveIntoZone(_ urls: [URL]) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: directoryURL.path,
            isDirectory: &isDirectory
        ),
        isDirectory.boolValue else {
            isDirectoryMissing = true
            return false
        }

        isDirectoryMissing = false
        var allSucceeded = true

        for source in urls {
            let normalized = source.standardizedFileURL
            guard FileManager.default.fileExists(atPath: normalized.path) else {
                allSucceeded = false
                continue
            }

            if normalized.deletingLastPathComponent().standardizedFileURL == directoryURL.standardizedFileURL {
                continue
            }

            let destination = Self.uniqueDestination(
                in: directoryURL,
                preferredName: normalized.lastPathComponent
            )

            do {
                try FileManager.default.moveItem(at: normalized, to: destination)
            } catch {
                NSLog("DeskBox move into zone failed: \(error)")
                allSucceeded = false
            }
        }

        reload()
        return allSucceeded
    }

    @discardableResult
    func moveToDesktop(_ url: URL) -> Bool {
        moveToDesktop([url])
    }

    @discardableResult
    func moveToDesktop(_ urls: [URL]) -> Bool {
        guard let desktop = FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first else {
            return false
        }

        var allSucceeded = true

        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                allSucceeded = false
                continue
            }

            let destination = Self.uniqueDestination(
                in: desktop,
                preferredName: url.lastPathComponent
            )

            do {
                try FileManager.default.moveItem(
                    at: url,
                    to: destination
                )
            } catch {
                NSLog("DeskBox move to Desktop failed: \(error)")
                allSucceeded = false
            }
        }

        reload()
        return allSucceeded
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func open(_ urls: [URL]) {
        for url in urls {
            NSWorkspace.shared.open(url)
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func uniqueDestination(in directory: URL, preferredName: String) -> URL {
        let fileManager = FileManager.default
        let original = directory.appendingPathComponent(preferredName)

        if !fileManager.fileExists(atPath: original.path) {
            return original
        }

        let nsName = preferredName as NSString
        let ext = nsName.pathExtension
        let base = nsName.deletingPathExtension

        var index = 2
        while true {
            let candidateName = ext.isEmpty
                ? "\(base) \(index)"
                : "\(base) \(index).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)

            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }
}
