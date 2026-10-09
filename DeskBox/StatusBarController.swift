import AppKit
import ServiceManagement

@MainActor
final class StatusBarController: NSObject {
    private let manager: ZoneManager
    private let statusItem: NSStatusItem
    private var workspacePanelController: WorkspaceSwitcherPanelController?
    private var settingsPanelController: SettingsPanelController?

    private let visibilityItem = NSMenuItem()
    private let workspaceItem = NSMenuItem()
    private let undoMoveItem = NSMenuItem()
    private let launchAtLoginItem = NSMenuItem()

    init(manager: ZoneManager) {
        self.manager = manager
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        workspacePanelController = WorkspaceSwitcherPanelController(
            manager: manager
        )
        settingsPanelController = SettingsPanelController(
            manager: manager
        )

        configureStatusItem()
        configureMenu()
        refreshMenuState()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "square.grid.2x2.fill",
                accessibilityDescription: "DeskBox"
            )
            button.toolTip = "DeskBox"
        }
    }

    private func configureMenu() {
        let menu = NSMenu()

        let workspacePanelItem = NSMenuItem(
            title: "打开工作区面板",
            action: #selector(toggleWorkspacePanel),
            keyEquivalent: ""
        )
        workspacePanelItem.target = self
        menu.addItem(workspacePanelItem)

        menu.addItem(.separator())

        visibilityItem.target = self
        visibilityItem.action = #selector(toggleVisibility)
        visibilityItem.keyEquivalent = "d"
        visibilityItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(visibilityItem)

        menu.addItem(.separator())

        workspaceItem.submenu = NSMenu()
        menu.addItem(workspaceItem)

        menu.addItem(.separator())

        let newZoneItem = NSMenuItem(
            title: "新建分区",
            action: #selector(createZone),
            keyEquivalent: "n"
        )
        newZoneItem.keyEquivalentModifierMask = [.command]
        newZoneItem.target = self
        menu.addItem(newZoneItem)

        let newNoteItem = NSMenuItem(
            title: "新建便签",
            action: #selector(createNote),
            keyEquivalent: ""
        )
        newNoteItem.target = self
        menu.addItem(newNoteItem)

        let newChecklistItem = NSMenuItem(
            title: "新建待办清单",
            action: #selector(createChecklist),
            keyEquivalent: ""
        )
        newChecklistItem.target = self
        menu.addItem(newChecklistItem)

        let newLauncherItem = NSMenuItem(
            title: "新建快捷入口",
            action: #selector(createLauncher),
            keyEquivalent: ""
        )
        newLauncherItem.target = self
        menu.addItem(newLauncherItem)

        let openFolderItem = NSMenuItem(
            title: "打开收纳文件夹",
            action: #selector(openStorageFolder),
            keyEquivalent: ""
        )
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        menu.addItem(.separator())

        undoMoveItem.target = self
        undoMoveItem.action = #selector(undoLastFileMove)
        undoMoveItem.keyEquivalent = "z"
        undoMoveItem.keyEquivalentModifierMask = [.command]
        menu.addItem(undoMoveItem)

        menu.addItem(.separator())

        launchAtLoginItem.target = self
        launchAtLoginItem.action = #selector(toggleLaunchAtLogin)
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(
            title: "关于 DeskBox",
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 DeskBox",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        menu.delegate = self
    }

    private func refreshMenuState() {
        visibilityItem.title = manager.areZonesHidden
            ? "显示当前工作区"
            : "隐藏当前工作区"

        workspaceItem.title = "工作区 · \(manager.currentWorkspaceName)"
        rebuildWorkspaceMenu()

        statusItem.button?.toolTip =
            "DeskBox · \(manager.currentWorkspaceName)"

        undoMoveItem.title = manager.undoFileMoveMenuTitle
        undoMoveItem.isEnabled = manager.canUndoLastFileMove

        let status = SMAppService.mainApp.status
        launchAtLoginItem.title = "开机自动启动"
        launchAtLoginItem.state = status == .enabled ? .on : .off
    }

    private func rebuildWorkspaceMenu() {
        let submenu = NSMenu()
        let workspaces = manager.workspaceList()

        for workspace in workspaces {
            let count = manager.workspaceItemCount(workspace.id)
            let item = NSMenuItem(
                title: "\(workspace.name) · \(count)",
                action: #selector(selectWorkspace(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = workspace.id.uuidString
            item.state = workspace.id == manager.currentWorkspaceID
                ? .on
                : .off
            submenu.addItem(item)
        }

        submenu.addItem(.separator())

        let newItem = NSMenuItem(
            title: "新建工作区…",
            action: #selector(createWorkspace),
            keyEquivalent: ""
        )
        newItem.target = self
        submenu.addItem(newItem)

        let renameItem = NSMenuItem(
            title: "重命名当前工作区…",
            action: #selector(renameCurrentWorkspace),
            keyEquivalent: ""
        )
        renameItem.target = self
        submenu.addItem(renameItem)

        submenu.addItem(.separator())

        let lockItem = NSMenuItem(
            title: manager.isCurrentWorkspaceLayoutLocked
                ? "解锁当前布局"
                : "锁定当前布局",
            action: #selector(toggleCurrentLayoutLock),
            keyEquivalent: ""
        )
        lockItem.target = self
        lockItem.state = manager.isCurrentWorkspaceLayoutLocked
            ? .on
            : .off
        submenu.addItem(lockItem)

        let saveLayoutItem = NSMenuItem(
            title: "保存当前布局",
            action: #selector(saveCurrentLayout),
            keyEquivalent: ""
        )
        saveLayoutItem.target = self
        submenu.addItem(saveLayoutItem)

        let restoreLayoutItem = NSMenuItem(
            title: "恢复保存的布局",
            action: #selector(restoreCurrentLayout),
            keyEquivalent: ""
        )
        restoreLayoutItem.target = self
        restoreLayoutItem.isEnabled =
            manager.currentWorkspaceHasLayoutSnapshot
        submenu.addItem(restoreLayoutItem)

        submenu.addItem(.separator())

        let deleteItem = NSMenuItem(
            title: "删除当前工作区…",
            action: #selector(deleteCurrentWorkspace),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.isEnabled = workspaces.count > 1
        submenu.addItem(deleteItem)

        workspaceItem.submenu = submenu
    }

    @objc
    private func toggleWorkspacePanel() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.workspacePanelController?.toggle(
                relativeTo: self.statusItem.button
            )
        }
    }

    @objc
    private func toggleVisibility() {
        _ = manager.toggleAllVisibility()
        refreshMenuState()
    }

    @objc
    private func selectWorkspace(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let id = UUID(uuidString: value) else {
            return
        }

        manager.switchWorkspace(to: id)
        refreshMenuState()
    }

    @objc
    private func createWorkspace() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.manager.createWorkspace()
            self.refreshMenuState()
        }
    }

    @objc
    private func renameCurrentWorkspace() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.manager.renameCurrentWorkspace()
            self.refreshMenuState()
        }
    }

    @objc
    private func toggleCurrentLayoutLock() {
        manager.toggleCurrentWorkspaceLayoutLock()
        refreshMenuState()
    }

    @objc
    private func saveCurrentLayout() {
        manager.saveCurrentWorkspaceLayoutSnapshot()
        refreshMenuState()
    }

    @objc
    private func restoreCurrentLayout() {
        manager.restoreCurrentWorkspaceLayoutSnapshot()
        refreshMenuState()
    }

    @objc
    private func deleteCurrentWorkspace() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.manager.deleteCurrentWorkspace()
            self.refreshMenuState()
        }
    }

    @objc
    private func createZone() {
        if manager.areZonesHidden {
            manager.showAll()
        }
        manager.createZone()
        refreshMenuState()
    }

    @objc
    private func createNote() {
        if manager.areZonesHidden {
            manager.showAll()
        }
        manager.createNote()
        refreshMenuState()
    }

    @objc
    private func createChecklist() {
        if manager.areZonesHidden {
            manager.showAll()
        }
        manager.createChecklist()
        refreshMenuState()
    }

    @objc
    private func createLauncher() {
        if manager.areZonesHidden {
            manager.showAll()
        }
        manager.createLauncher()
        refreshMenuState()
    }

    @objc
    private func openStorageFolder() {
        manager.openStorageFolder()
    }

    @objc
    private func undoLastFileMove() {
        manager.undoLastFileMove()
        refreshMenuState()
    }

    @objc
    private func openSettings() {
        settingsPanelController?.show(section: .general)
    }

    @objc
    private func openAbout() {
        settingsPanelController?.show(section: .about)
    }

    @objc
    private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
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

        refreshMenuState()
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }
}
