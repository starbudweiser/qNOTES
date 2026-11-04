import AppKit
import Carbon.HIToolbox
import SwiftUI
import qNOTESCore

/// Icône dans la barre de menu + volet de notes rapide (clic gauche), menu (clic droit).
@MainActor
final class MenuBarController: NSObject {
    private let model: AppModel
    private let store: NoteStore
    private let popover = NSPopover()
    private var item: NSStatusItem?
    var openApp: () -> Void = {}
    var openSettings: () -> Void = {}

    init(model: AppModel, store: NoteStore) {
        self.model = model
        self.store = store
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: QuickView(model: model, store: store, openApp: { [weak self] in
            self?.popover.performClose(nil)
            self?.openApp()
        }))
    }

    var isVisible: Bool { item != nil }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = status.button {
                button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: L("menubar.tooltip"))
                button.image?.isTemplate = true
                button.toolTip = L("menubar.tooltip")
                button.target = self
                button.action = #selector(clicked)
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            item = status
        } else if !visible, let status = item {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(status)
            item = nil
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { toggle() }
    }

    func toggle() {
        popover.isShown ? popover.performClose(nil) : show()
    }

    func show() {
        guard let button = item?.button else { return }
        if model.selectedID == nil || store.note(model.selectedID!) == nil {
            if let first = store.notes.first { model.selectedID = first.id } else { model.newNote() }
        }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.popover.contentViewController?.view,
                  let text = view.firstDescendant(ofType: NoteTextView.self, where: { _ in true }) else { return }
            text.window?.makeFirstResponder(text)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ key: String = "") {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.target = self
            menu.addItem(entry)
        }
        add(L("menubar.open"), #selector(menuOpen))
        add(L("note.new"), #selector(menuNew))
        add(L("menu.settings"), #selector(menuSettings))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quit)
        item?.menu = menu
        item?.button?.performClick(nil)
        item?.menu = nil   // sans cela le clic gauche ouvrirait aussi le menu
    }

    @objc private func menuOpen() { openApp() }
    @objc private func menuNew() { model.newNote(); show() }
    @objc private func menuSettings() { openSettings() }
}

// MARK: Volet

private let dotColors: [Color] = [
    Color(red: 1.00, green: 0.78, blue: 0.10), Color(red: 1.00, green: 0.52, blue: 0.10), Color(red: 0.96, green: 0.26, blue: 0.24),
    Color(red: 0.62, green: 0.30, blue: 0.86), Color(red: 0.20, green: 0.48, blue: 0.96), Color(red: 0.10, green: 0.70, blue: 0.80),
    Color(red: 0.20, green: 0.74, blue: 0.30),
]

struct QuickView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: NoteStore
    var openApp: () -> Void = {}
    @State private var selection = ""
    @AppStorage(Prefs.fontSize) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.separator) private var separator = Separators.presets[0]
    @AppStorage(Prefs.layoutMode) private var layout = true

    var body: some View {
        let note = model.selectedID.flatMap { store.note($0) }
        VStack(spacing: 0) {
            HStack(spacing: Socle.M.space2) {
                ForEach(Array(store.notes.prefix(dotColors.count).enumerated()), id: \.element.id) { index, entry in
                    Dot(color: dotColors[index], selected: entry.id == model.selectedID, title: entry.title.isEmpty ? L("note.untitled") : entry.title)
                        .onTapGesture { model.selectedID = entry.id }
                }
                Spacer(minLength: Socle.M.space2)
                Button { model.newNote() } label: { Image(systemName: "plus").font(.system(size: 13)) }
                    .buttonStyle(SocleButtonStyle(.tertiary, height: 28)).frame(width: 34)
                    .help(L("note.new"))
                Menu {
                    ForEach(store.notes.prefix(60)) { entry in
                        Button((entry.pinned ? "📌 " : "") + (entry.title.isEmpty ? L("note.untitled") : entry.title)) { model.selectedID = entry.id }
                    }
                } label: { Image(systemName: "list.bullet").font(.system(size: 13)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(L("menubar.notes"))
            }
            .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2)
            Rectangle().fill(Socle.C.border).frame(height: 1)
            if let note {
                NoteEditor(noteID: note.id, text: note.text, fontSize: fontSize, separator: separator, layout: layout,
                           onChange: { store.update(id: note.id, text: $0) },
                           onSelection: { selection = $0 })
            } else {
                Spacer()
            }
            Rectangle().fill(Socle.C.border).frame(height: 1)
            HStack(spacing: Socle.M.space3) {
                let counts = TextCounts(selection.isEmpty ? (note?.text ?? "") : selection)
                Text(L("count.words", counts.words) + " · " + L("count.chars", counts.characters))
                    .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                Spacer()
                Button(action: openApp) { Image(systemName: "arrow.up.forward.app").font(.system(size: 13)) }
                    .buttonStyle(SocleButtonStyle(.tertiary, height: 26)).frame(width: 32)
                    .help(L("menubar.open"))
            }
            .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space1_5)
            .background(Socle.C.surfaceRaised)
        }
        .frame(width: 440, height: 520)
        .background(Socle.C.surface)
    }
}

private struct Dot: View {
    let color: Color
    let selected: Bool
    let title: String

    var body: some View {
        Circle().fill(color).frame(width: 14, height: 14)
            .overlay(Circle().stroke(Socle.C.textStrong, lineWidth: selected ? 2 : 0).padding(-3))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .help(title)
    }
}

// MARK: Raccourci global

/// Raccourci clavier global (Carbon : aucune autorisation d'accessibilité nécessaire).
@MainActor
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) { self.onPress = onPress }

    var isRegistered: Bool { ref != nil }

    func register(keyCode: Int = kVK_ANSI_N, modifiers: Int = controlKey | optionKey) {
        guard ref == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { hotKey.onPress() } }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x714E_4F54), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
    }
}
