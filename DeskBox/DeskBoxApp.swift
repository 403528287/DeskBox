import SwiftUI
import AppKit

enum DeskBoxBundleMigration {
    private static let oldBundleID =
        "com.deskbox.prototype"
    private static let migrationKey =
        "DeskBox.BundleMigration.prototypeToWFB.v1"
    private static let sessionRunningKey =
        "DeskBox.SessionRunning.v1"

    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard

        guard !defaults.bool(forKey: migrationKey)
        else {
            return
        }

        if let oldDomain = defaults.persistentDomain(
            forName: oldBundleID
        ) {
            for (key, value) in oldDomain {
                guard key.hasPrefix("DeskBox."),
                      key != sessionRunningKey,
                      key != migrationKey,
                      defaults.object(forKey: key) == nil
                else {
                    continue
                }

                defaults.set(value, forKey: key)
            }
        }

        defaults.set(true, forKey: migrationKey)
        defaults.synchronize()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sessionRunningKey =
        "DeskBox.SessionRunning.v1"

    private var zoneManager: ZoneManager?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏常驻工具：不占 Dock、不作为普通前台应用出现。
        NSApp.setActivationPolicy(.accessory)

        DeskBoxBundleMigration.migrateIfNeeded()

        let defaults = UserDefaults.standard
        let previousSessionEndedUnexpectedly =
            defaults.bool(forKey: sessionRunningKey)
        defaults.set(true, forKey: sessionRunningKey)

        let manager = ZoneManager()
        zoneManager = manager

        if previousSessionEndedUnexpectedly {
            manager.createRecoverySnapshotAfterUncleanExit()
        }

        if DeskBoxPreferences.showWorkspaceAtLaunch {
            manager.showAll()
        } else {
            manager.hideAll()
        }

        statusBarController = StatusBarController(manager: manager)

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.35
        ) {
            manager.presentStartupRecoveryIfNeeded()
        }
    }

    func applicationWillTerminate(
        _ notification: Notification
    ) {
        UserDefaults.standard.set(
            false,
            forKey: sessionRunningKey
        )
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
