import AppKit
import RuleBoxCore
import SwiftUI

@MainActor
final class RuleBoxAppDelegate: NSObject, NSApplicationDelegate {
    let store = RuleBoxStore()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMenuBarItem()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = item.button {
            let img = NSImage(systemSymbolName: "tray.full.fill", accessibilityDescription: "RuleBox")
            img?.isTemplate = true
            btn.image = img
        }
        item.menu = buildStatusMenu()
        self.statusItem = item
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let statusTitle = store.workspace.watcherActive
            ? "Watcher Active (\(store.workspace.folders.count) folders)"
            : "Watcher Paused"
        let header = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let pending = NSMenuItem(title: "\(store.totalPendingMatches) file(s) ready to organize", action: nil, keyEquivalent: "")
        pending.isEnabled = false
        menu.addItem(pending)

        menu.addItem(.separator())

        let toggleItem = NSMenuItem(
            title: store.workspace.watcherActive ? "Pause Watcher" : "Resume Watcher",
            action: #selector(toggleWatcherAction),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let runAllItem = NSMenuItem(title: "Run All Rules Now", action: #selector(runAllAction), keyEquivalent: "r")
        runAllItem.target = self
        menu.addItem(runAllItem)

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open RuleBox", action: #selector(openMainWindow), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "Quit RuleBox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    @objc private func toggleWatcherAction() {
        store.toggleWatcher()
        statusItem?.menu = buildStatusMenu()
    }

    @objc private func runAllAction() {
        store.runAllFoldersNow()
        statusItem?.menu = buildStatusMenu()
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for win in NSApp.windows where win.canBecomeMain {
            win.makeKeyAndOrderFront(nil)
            return
        }
    }
}

@main
struct RuleBoxApp: App {
    @NSApplicationDelegateAdaptor(RuleBoxAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("RuleBox") {
            MainWorkspaceView(store: delegate.store)
                .frame(minWidth: 1040, minHeight: 660)
        }
        .defaultSize(width: 1240, height: 780)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Watched Folder…") {
                    pickFolderAndAdd(store: delegate.store)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("New Rule") {
                    if let folder = delegate.store.selectedFolder {
                        delegate.store.addNewRule(to: folder.id)
                    }
                }
                .keyboardShortcut("n", modifiers: [.command])

                Divider()

                Button("Run Selected Folder Now") {
                    if let folder = delegate.store.selectedFolder {
                        delegate.store.runFolderNow(id: folder.id)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Refresh Dry-Run Preview") {
                    delegate.store.refreshAllPreviews()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
func pickFolderAndAdd(store: RuleBoxStore) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Watch Folder"
    if panel.runModal() == .OK, let url = panel.url {
        store.addFolder(url: url)
    }
}

@MainActor
func pickDestinationFolder(initialPath: String? = nil) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Choose Folder"
    if let initialPath, !initialPath.isEmpty {
        panel.directoryURL = URL(fileURLWithPath: initialPath)
    }
    if panel.runModal() == .OK, let url = panel.url {
        return url.path
    }
    return nil
}
