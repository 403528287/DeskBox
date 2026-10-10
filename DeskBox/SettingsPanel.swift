import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum DeskBoxPreferences {
    static let showWorkspaceAtLaunchKey =
        "DeskBox.ShowWorkspaceAtLaunch.v1"

    static var showWorkspaceAtLaunch: Bool {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(
                forKey: showWorkspaceAtLaunchKey
            ) != nil else {
                return true
            }
            return defaults.bool(
                forKey: showWorkspaceAtLaunchKey
            )
        }
        set {
            UserDefaults.standard.set(
                newValue,
                forKey: showWorkspaceAtLaunchKey
            )
        }
    }
}

@MainActor
final class DeskBoxSettingsStore: ObservableObject {
    @Published var showWorkspaceAtLaunch: Bool
    @Published var launchAtLoginEnabled = false
    @Published var selectedSection: SettingsSection = .general
    @Published var recentOperations: [FileMoveTransaction] = []
    @Published var latestUndoableOperationID: UUID?

    let manager: ZoneManager

    init(manager: ZoneManager) {
        self.manager = manager
        self.showWorkspaceAtLaunch =
            DeskBoxPreferences.showWorkspaceAtLaunch
        refreshLaunchAtLogin()
        refreshRecentOperations()
    }

    var storagePath: String {
        manager.storageFolderURL.path
    }

    var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.0"

        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"

        return "版本 \(version)（\(build)）"
    }

    var appIcon: NSImage {
        if let iconURL = Bundle.main.url(
            forResource: "AppIcon",
            withExtension: "icns"
        ),
        let icon = NSImage(contentsOf: iconURL) {
            return icon
        }

        return NSApplication.shared.applicationIconImage
    }

    func setShowWorkspaceAtLaunch(_ enabled: Bool) {
        showWorkspaceAtLaunch = enabled
        DeskBoxPreferences.showWorkspaceAtLaunch = enabled
    }

    func refreshLaunchAtLogin() {
        launchAtLoginEnabled =
            SMAppService.mainApp.status == .enabled
    }

    func refreshRecentOperations() {
        recentOperations =
            manager.recentFileMoveTransactions()
        latestUndoableOperationID =
            manager.latestUndoableFileMoveID
    }

    func undoLatestOperation() {
        manager.undoLastFileMove()
        refreshRecentOperations()
    }

    func folderDisplayName(for path: String) -> String {
        let url = URL(
            fileURLWithPath: path
        ).deletingLastPathComponent().standardizedFileURL

        if let desktop = FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first?.standardizedFileURL,
        url == desktop {
            return "桌面"
        }

        let root = manager.storageFolderURL.standardizedFileURL
        if url.path.hasPrefix(root.path) {
            let relative = url.path
                .dropFirst(root.path.count)
                .trimmingCharacters(
                    in: CharacterSet(
                        charactersIn: "/"
                    )
                )

            if relative.isEmpty {
                return "DeskBox"
            }
            return String(relative)
        }

        return url.lastPathComponent.isEmpty
            ? url.path
            : url.lastPathComponent
    }

    func exportConfigurationBackup() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.title = "导出 DeskBox 配置"
        panel.prompt = "导出"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        formatter.dateFormat = "yyyy-MM-dd"

        panel.nameFieldStringValue =
            "DeskBox-配置备份-\(formatter.string(from: Date())).json"

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            let data = try manager.configurationBackupData()
            try data.write(
                to: url,
                options: .atomic
            )

            showMessage(
                title: "配置已导出",
                message: "备份只包含 DeskBox 的工作区、布局、便签、待办和快捷入口，不包含任何真实文件。"
            )
        } catch {
            showMessage(
                title: "导出失败",
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    func importConfigurationBackup() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "恢复 DeskBox 配置"
        panel.prompt = "选择备份"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = "恢复这个 DeskBox 配置？"
        confirmation.informativeText = """
        工作区、便签、待办、快捷入口和布局会恢复为备份中的状态。

        DeskBox 不会删除、覆盖或打包任何真实文件。当前存在但备份中没有的文件分区也会保留。

        恢复前还会自动保存一份当前配置，便于回滚。
        """
        confirmation.addButton(withTitle: "恢复")
        confirmation.addButton(withTitle: "取消")

        guard confirmation.runModal()
                == .alertFirstButtonReturn else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            try manager.restoreConfigurationBackup(
                from: data
            )

            showWorkspaceAtLaunch =
                DeskBoxPreferences.showWorkspaceAtLaunch
            refreshRecentOperations()

            showMessage(
                title: "配置恢复完成",
                message: "DeskBox 的界面配置已经恢复。真实文件和文件夹没有被删除或覆盖。"
            )
        } catch {
            showMessage(
                title: "恢复失败",
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    private func showMessage(
        title: String,
        message: String,
        style: NSAlert.Style = .informational
    ) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "开机启动设置失败"
            alert.informativeText = """
            \(error.localizedDescription)

            当前是开发测试版时，macOS 可能要求先把 DeskBox 正式安装到“应用程序”文件夹后才能启用开机启动。
            """
            alert.addButton(withTitle: "知道了")
            alert.runModal()
        }

        refreshLaunchAtLogin()
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "通用"
    case history = "最近操作"
    case about = "关于"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:
            return "gearshape"
        case .history:
            return "clock.arrow.circlepath"
        case .about:
            return "info.circle"
        }
    }
}

struct DeskBoxSettingsView: View {
    @ObservedObject var store: DeskBoxSettingsStore

    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 0) {
                sidebar

                Divider()
                    .opacity(0.24)

                content
            }
        }
        .frame(width: 560, height: 410)
        .background {
            ZStack {
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 28,
                        bottomLeading: 38,
                        bottomTrailing: 28,
                        topTrailing: 38
                    ),
                    style: .continuous
                )
                .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.20),
                        Color.blue.opacity(0.055),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 28,
                    bottomLeading: 38,
                    bottomTrailing: 28,
                    topTrailing: 38
                ),
                style: .continuous
            )
        )
        .overlay {
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 28,
                    bottomLeading: 38,
                    bottomTrailing: 28,
                    topTrailing: 38
                ),
                style: .continuous
            )
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.68),
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .allowsHitTesting(false)
        }
    }

    private var header: some View {
        ZStack {
            WindowDragHandle(onDoubleClick: {})
                .contentShape(Rectangle())

            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 12,
                        style: .continuous
                    )
                    .fill(.thinMaterial)
                    .frame(width: 38, height: 38)

                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            Color.primary.opacity(0.72)
                        )
                }
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DeskBox 设置")
                        .font(.system(size: 15, weight: .bold))

                    Text("桌面工作区与应用偏好")
                        .font(.system(size: 10.5))
                        .foregroundStyle(
                            Color.primary.opacity(0.58)
                        )
                }
                .allowsHitTesting(false)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(.thinMaterial)
                        )
                }
                .buttonStyle(.plain)
                .deskBoxHeaderHover()
                .help("关闭")
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 66)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.blue.opacity(0.045),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .bottom) {
            Divider()
                .opacity(0.22)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 6) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    withAnimation(
                        .easeInOut(duration: 0.16)
                    ) {
                        store.selectedSection = section
                    }

                    if section == .history {
                        store.refreshRecentOperations()
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: section.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 18)

                        Text(section.rawValue)
                            .font(.system(size: 12.5, weight: .semibold))

                        Spacer()
                    }
                    .foregroundStyle(
                        store.selectedSection == section
                            ? Color.primary
                            : Color.primary.opacity(0.58)
                    )
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(
                            cornerRadius: 10,
                            style: .continuous
                        )
                        .fill(
                            store.selectedSection == section
                                ? Color.primary.opacity(0.07)
                                : Color.clear
                        )
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 132)
        .background(
            Color.primary.opacity(0.018)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch store.selectedSection {
        case .general:
            generalContent
        case .history:
            historyContent
        case .about:
            aboutContent
        }
    }

    private var generalContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsTitle(
                    "通用",
                    subtitle: "控制 DeskBox 的启动和桌面行为"
                )

                settingsCard {
                    Toggle(
                        isOn: Binding(
                            get: {
                                store.showWorkspaceAtLaunch
                            },
                            set: { enabled in
                                store.setShowWorkspaceAtLaunch(
                                    enabled
                                )
                            }
                        )
                    ) {
                        settingLabel(
                            title: "启动时显示当前工作区",
                            subtitle: "关闭后仅驻留菜单栏，需要时再手动显示",
                            icon: "rectangle.on.rectangle"
                        )
                    }
                    .toggleStyle(.switch)

                    Divider()
                        .opacity(0.20)

                    Toggle(
                        isOn: Binding(
                            get: {
                                store.launchAtLoginEnabled
                            },
                            set: { enabled in
                                store.setLaunchAtLogin(enabled)
                            }
                        )
                    ) {
                        settingLabel(
                            title: "开机自动启动",
                            subtitle: "登录 macOS 后自动启动 DeskBox",
                            icon: "power"
                        )
                    }
                    .toggleStyle(.switch)
                }

                settingsTitle(
                    "数据",
                    subtitle: "DeskBox 的文件收纳位置"
                )

                settingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("收纳文件夹")
                                .font(.system(size: 12.5, weight: .semibold))

                            Text(store.storagePath)
                                .font(.system(size: 10.5))
                                .foregroundStyle(
                                    Color.primary.opacity(0.60)
                                )
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button("打开") {
                            store.manager.openStorageFolder()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                settingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.timemachine")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("配置备份")
                                .font(.system(size: 12.5, weight: .semibold))

                            Text("只备份工作区、布局、便签、待办和快捷入口，不包含真实文件")
                                .font(.system(size: 10.5))
                                .foregroundStyle(
                                    Color.primary.opacity(0.58)
                                )
                                .lineLimit(2)
                        }

                        Spacer()

                        HStack(spacing: 7) {
                            Button("导出…") {
                                store.exportConfigurationBackup()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("恢复…") {
                                store.importConfigurationBackup()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                settingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("快速隐藏 / 显示")
                                .font(.system(size: 12.5, weight: .semibold))

                            Text("当前工作区")
                                .font(.system(size: 10.5))
                                .foregroundStyle(
                                    Color.primary.opacity(0.58)
                                )
                        }

                        Spacer()

                        Text("⌘⇧D")
                            .font(
                                .system(
                                    size: 11,
                                    weight: .semibold,
                                    design: .rounded
                                )
                            )
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(
                                RoundedRectangle(
                                    cornerRadius: 7,
                                    style: .continuous
                                )
                                .fill(Color.primary.opacity(0.06))
                            )
                    }
                }
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var historyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    settingsTitle(
                        "最近操作",
                        subtitle: "保留最近 50 次 DeskBox 文件移动记录"
                    )

                    Spacer()

                    if store.latestUndoableOperationID != nil {
                        Button {
                            store.undoLatestOperation()
                        } label: {
                            Label(
                                "撤销最近一次",
                                systemImage: "arrow.uturn.backward"
                            )
                            .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if store.recentOperations.isEmpty {
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.primary.opacity(0.05))
                                .frame(width: 48, height: 48)

                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(
                                    Color.primary.opacity(0.42)
                                )
                        }

                        Text("还没有文件移动记录")
                            .font(.system(size: 12.5, weight: .semibold))

                        Text("通过 DeskBox 移动文件后，记录会显示在这里")
                            .font(.system(size: 10.5))
                            .foregroundStyle(
                                Color.primary.opacity(0.56)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 76)
                } else {
                    LazyVStack(spacing: 9) {
                        ForEach(store.recentOperations) { transaction in
                            historyCard(transaction)
                        }
                    }
                }
            }
            .padding(22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            store.refreshRecentOperations()
        }
    }

    private func historyCard(
        _ transaction: FileMoveTransaction
    ) -> some View {
        let firstItem = transaction.items.first
        let fileNames = transaction.items
            .prefix(2)
            .map {
                URL(
                    fileURLWithPath: $0.sourcePath
                ).lastPathComponent
            }

        let sourceName = firstItem.map {
            store.folderDisplayName(for: $0.sourcePath)
        } ?? "—"

        let destinationName = firstItem.map {
            store.folderDisplayName(for: $0.destinationPath)
        } ?? "—"

        let isLatestUndoable =
            store.latestUndoableOperationID == transaction.id
                && !transaction.undoneValue

        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(
                        cornerRadius: 9,
                        style: .continuous
                    )
                    .fill(
                        transaction.undoneValue
                            ? Color.primary.opacity(0.045)
                            : Color.accentColor.opacity(0.11)
                    )
                    .frame(width: 34, height: 34)

                    Image(
                        systemName: transaction.undoneValue
                            ? "arrow.uturn.backward.circle.fill"
                            : "arrow.right.circle.fill"
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        transaction.undoneValue
                            ? Color.secondary
                            : Color.accentColor
                    )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(transaction.summary)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)

                    Text(
                        transaction.date.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(
                        Color.primary.opacity(0.52)
                    )
                }

                Spacer()

                if transaction.undoneValue {
                    Text("已撤销")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(
                            Color.primary.opacity(0.58)
                        )
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.055))
                        )
                } else if isLatestUndoable {
                    Button("撤销") {
                        store.undoLatestOperation()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            HStack(spacing: 7) {
                Text(sourceName)
                    .lineLimit(1)

                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(
                        Color.primary.opacity(0.38)
                    )

                Text(destinationName)
                    .lineLimit(1)

                Spacer()
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(
                Color.primary.opacity(0.64)
            )

            HStack(spacing: 5) {
                Image(systemName: "doc")
                    .font(.system(size: 9.5))
                    .foregroundStyle(
                        Color.primary.opacity(0.42)
                    )

                Text(fileNames.joined(separator: "、"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(
                        Color.primary.opacity(0.58)
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)

                if transaction.items.count > 2 {
                    Text("等 \(transaction.items.count) 项")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(
                            Color.primary.opacity(0.48)
                        )
                }

                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .fill(.thinMaterial)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.24),
                lineWidth: 1
            )
        }
        .opacity(transaction.undoneValue ? 0.72 : 1)
    }

    private var aboutContent: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(nsImage: store.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 92, height: 92)
                .shadow(
                    color: Color.black.opacity(0.16),
                    radius: 14,
                    x: 0,
                    y: 8
                )

            VStack(spacing: 5) {
                Text("DeskBox")
                    .font(.system(size: 24, weight: .bold))

                Text("让桌面保持井然有序")
                    .font(.system(size: 12.5))
                    .foregroundStyle(
                        Color.primary.opacity(0.62)
                    )

                Text(store.versionText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(
                        Color.primary.opacity(0.52)
                    )
                    .padding(.top, 3)
            }

            VStack(spacing: 7) {
                Label(
                    "文件分区使用真实文件夹存储",
                    systemImage: "folder.badge.checkmark"
                )
                Label(
                    "工作区只改变 DeskBox 内的组织关系",
                    systemImage: "rectangle.3.group"
                )
                Label(
                    "删除快捷入口不会删除原文件",
                    systemImage: "link"
                )
            }
            .font(.system(size: 11))
            .foregroundStyle(
                Color.primary.opacity(0.60)
            )

            Spacer()

            Text("Made for macOS")
                .font(.system(size: 10))
                .foregroundStyle(
                    Color.primary.opacity(0.46)
                )
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 30)
    }

    private func settingsTitle(
        _ title: String,
        subtitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .bold))

            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(
                    Color.primary.opacity(0.60)
                )
        }
    }

    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 12) {
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
            .fill(.thinMaterial)
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: 15,
                style: .continuous
            )
            .stroke(
                Color.white.opacity(0.25),
                lineWidth: 1
            )
        }
    }

    private func settingLabel(
        title: String,
        subtitle: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(
                        Color.primary.opacity(0.58)
                    )
            }
        }
    }
}

@MainActor
final class DeskBoxSettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SettingsPanelController: NSObject {
    private let manager: ZoneManager
    private let store: DeskBoxSettingsStore
    private var panel: DeskBoxSettingsPanel?

    init(manager: ZoneManager) {
        self.manager = manager
        self.store = DeskBoxSettingsStore(manager: manager)
        super.init()
    }

    func show(section: SettingsSection = .general) {
        store.selectedSection = section
        store.showWorkspaceAtLaunch =
            DeskBoxPreferences.showWorkspaceAtLaunch
        store.refreshLaunchAtLogin()
        store.refreshRecentOperations()

        NSApp.activate(ignoringOtherApps: true)

        let panel = panel ?? makePanel()
        positionIfNeeded(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func positionIfNeeded(_ panel: DeskBoxSettingsPanel) {
        guard !panel.isVisible else { return }

        if let screen = NSScreen.main?.visibleFrame {
            let x = screen.midX - panel.frame.width / 2
            let y = screen.midY - panel.frame.height / 2 + 24
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func makePanel() -> DeskBoxSettingsPanel {
        let rootView = DeskBoxSettingsView(
            store: store,
            onClose: { [weak self] in
                self?.hide()
            }
        )

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(
            x: 0,
            y: 0,
            width: 560,
            height: 410
        )

        let panel = DeskBoxSettingsPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 560,
                height: 410
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

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
