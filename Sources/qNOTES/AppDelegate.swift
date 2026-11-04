import AppKit
import SwiftUI
import UniformTypeIdentifiers
import qNOTESCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store: NoteStore
    let model: AppModel
    let backups: BackupScheduler
    let updates = UpdateEngine.shared
    private var window: NSWindow?
    private var settingsWindow: NSWindow?

    override init() {
        let directory = (Prefs.sync ? NoteStore.iCloudDirectory : nil) ?? NoteStore.localDirectory
        store = NoteStore(directory: directory)
        model = AppModel(store: store)
        backups = BackupScheduler(store: store)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Socle.apply()
        buildMenu()
        store.startWatching()
        backups.start()
        updates.configure(repo: "qNOTES", lang: { Bundle.main.preferredLocalizations.first ?? "en" })
        updates.autoCheck = { Prefs.defaults.object(forKey: Prefs.autoUpdate) as? Bool ?? true }
        updates.start()
        if !CommandLine.arguments.contains(where: { $0.hasPrefix("--capture") }) { showMainWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    // MARK: Fenêtres

    func makeMainWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "qNOTES"
        w.minSize = NSSize(width: 700, height: 440)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: ContentView(model: model, store: store))
        w.socleCenter()
        return w
    }

    func showMainWindow() {
        if window == nil { window = makeMainWindow() }
        window?.present()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let actions = SettingsActions(
                applySync: { [weak self] in self?.applySync() },
                backupNow: { [weak self] in self?.backups.backupNow() ?? false },
                restore: { [weak self] in self?.backups.restore($0) ?? false },
                checkUpdates: { [weak self] in self?.updates.checkNow() })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = L("menu.settings.title")
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(actions: actions))
            w.socleCenter()
            settingsWindow = w
        }
        settingsWindow?.present()
    }

    @objc func showAbout() { About.show() }

    func applySync() {
        if Prefs.sync, let cloud = NoteStore.iCloudDirectory {
            store.switchDirectory(to: cloud)
        } else {
            store.switchDirectory(to: NoteStore.localDirectory)
        }
    }

    // MARK: Actions de menu

    @objc func newNote() {
        showMainWindow()
        model.newNote()
    }

    @objc func deleteNote() {
        if let id = model.selectedID { model.requestDelete(id) }
    }

    @objc func exportNote() {
        guard let id = model.selectedID, let note = store.note(id) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = (note.title.isEmpty ? L("note.untitled") : note.title).replacingOccurrences(of: "/", with: "-") + ".md"
        if panel.runModal() == .OK, let url = panel.url { try? note.text.write(to: url, atomically: true, encoding: .utf8) }
    }

    @objc func togglePin() {
        guard let id = model.selectedID, let note = store.note(id) else { return }
        store.setPinned(id: id, !note.pinned)
    }

    @objc func focusSearch() {
        showMainWindow()
        if let field = window?.contentView?.firstDescendant(ofType: NSTextField.self, where: { $0.isEditable }) {
            window?.makeFirstResponder(field)
        }
    }

    // MARK: Menus

    private func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        i.target = target
        return i
    }

    private func buildMenu() {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem()
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            holder.submenu = menu
            main.addItem(holder)
        }
        let updateItem = item(Updater.text("menu", lang: updates.currentLang), #selector(UpdateMenuTarget.fire), target: UpdateMenuTarget.shared)
        add("qNOTES", [
            item(L("about.menu"), #selector(showAbout), target: self),
            updateItem,
            .separator(),
            item(L("menu.settings"), #selector(showSettings), ",", target: self),
            .separator(),
            item(L("menu.hide"), #selector(NSApplication.hide(_:)), "h"),
            item(L("menu.hideothers"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item(L("menu.showall"), #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item(L("menu.quit"), #selector(NSApplication.terminate(_:)), "q"),
        ])
        add(L("menu.file"), [
            item(L("note.new"), #selector(newNote), "n", target: self),
            item(L("menu.pin"), #selector(togglePin), "p", [.command, .shift], target: self),
            item(L("menu.export"), #selector(exportNote), "e", [.command, .shift], target: self),
            .separator(),
            item(L("note.delete"), #selector(deleteNote), String(UnicodeScalar(NSBackspaceCharacter)!), .command, target: self),
            .separator(),
            item(L("menu.close"), #selector(NSWindow.performClose(_:)), "w"),
        ])
        add(L("menu.edit"), [
            item(L("menu.undo"), Selector(("undo:")), "z"),
            item(L("menu.redo"), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item(L("menu.cut"), #selector(NSText.cut(_:)), "x"),
            item(L("menu.copy"), #selector(NSText.copy(_:)), "c"),
            item(L("menu.paste"), #selector(NSText.paste(_:)), "v"),
            item(L("menu.selectall"), #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item(L("menu.find"), #selector(NSResponder.performTextFinderAction(_:)), "f").tagged(1),
            item(L("menu.search"), #selector(focusSearch), "f", [.command, .option], target: self),
        ])
        add(L("menu.window"), [
            item(L("menu.minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"),
            item(L("menu.zoom"), #selector(NSWindow.performZoom(_:))),
        ])
        NSApp.mainMenu = main
        NSApp.windowsMenu = main.items.last?.submenu
    }
}

private extension NSMenuItem {
    func tagged(_ tag: Int) -> NSMenuItem { self.tag = tag; return self }
}

extension NSView {
    func firstDescendant<T: NSView>(ofType: T.Type, where match: (T) -> Bool) -> T? {
        for sub in subviews {
            if let t = sub as? T, match(t) { return t }
            if let found = sub.firstDescendant(ofType: ofType, where: match) { return found }
        }
        return nil
    }
}
