import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var zoneManager: ZoneManager?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏常驻工具：不占 Dock、不作为普通前台应用出现。
        NSApp.setActivationPolicy(.accessory)

        let manager = ZoneManager()
        zoneManager = manager
        manager.showAll()

        statusBarController = StatusBarController(manager: manager)
    }

    func applicationDidResignActive(_ notification: Notification) {
        zoneManager?.selectionState.clear()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct DeskBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
