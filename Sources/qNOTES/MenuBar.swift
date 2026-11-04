import AppKit
import Carbon.HIToolbox
import SwiftUI
import qNOTESCore

/// Fenêtre du volet : sans cadre, redimensionnable, prend le focus clavier, se ferme avec Échap.
private final class QuickPanel: NSPanel {
    var onEscape: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape() }
}

/// Icône dans la barre de menu + volet de notes rapide, redimensionnable (clic gauche), menu (clic droit).
@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 440, height: 520)
    static let minSize = NSSize(width: 340, height: 280)
    static let sizeKeys = ("quickWidth", "quickHeight")

    private let model: AppModel
    private let store: NoteStore
    private let panel: QuickPanel
    private var item: NSStatusItem?
    private var lastShown = Date.distantPast
    /// Le volet était-il affiché quand le bouton a été enfoncé ? Le clic lui fait perdre le focus (il se ferme) avant l'action.
    private var visibleAtMouseDown: Bool?
    private var mouseMonitor: Any?
    private var resizeStart: (mouse: NSPoint, frame: NSRect)?
    var openApp: () -> Void = {}
    var openSettings: () -> Void = {}

    init(model: AppModel, store: NoteStore) {
        self.model = model
        self.store = store
        panel = QuickPanel(contentRect: NSRect(origin: .zero, size: Self.savedSize()), styleMask: [.borderless, .resizable],
                           backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = Self.minSize
        panel.maxSize = NSSize(width: 1200, height: 1400)
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close() }
        let content = QuickView(model: model, store: store,
                                openApp: { [weak self] in self?.close(); self?.openApp() },
                                beginResize: { [weak self] in self?.beginResize() },
                                resize: { [weak self] in self?.resize() })
        let host = NSHostingView(rootView: content)
        host.wantsLayer = true
        host.layer?.cornerRadius = 12
        host.layer?.masksToBounds = true
        panel.contentView = host
    }

    /// Gros point blanc (image non « template » : il reste blanc quelle que soit la barre de menu).
    private static func whiteDot() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func savedSize() -> NSSize {
        let d = Prefs.defaults
        let w = d.double(forKey: sizeKeys.0), h = d.double(forKey: sizeKeys.1)
        return w >= minSize.width && h >= minSize.height ? NSSize(width: w, height: h) : defaultSize
    }

    private func saveSize() {
        Prefs.defaults.set(Double(panel.frame.width), forKey: Self.sizeKeys.0)
        Prefs.defaults.set(Double(panel.frame.height), forKey: Self.sizeKeys.1)
    }

    var isVisible: Bool { item != nil }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = status.button {
                button.image = Self.whiteDot()
                button.image?.accessibilityDescription = L("menubar.tooltip")
                button.toolTip = L("menubar.tooltip")
                button.target = self
                button.action = #selector(clicked)
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            item = status
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                if let self, event.window != nil, event.window === self.item?.button?.window { self.visibleAtMouseDown = self.panel.isVisible }
                return event
            }
        } else if !visible, let status = item {
            close()
            if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor); mouseMonitor = nil }
            NSStatusBar.system.removeStatusItem(status)
            item = nil
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        // Un second clic sur l'icône referme le volet ; il ne doit pas le rouvrir parce que le clic l'a déjà fait fermer.
        let wasVisible = visibleAtMouseDown ?? panel.isVisible
        visibleAtMouseDown = nil
        if wasVisible { close() } else { show() }
    }

    func toggle() {
        if panel.isVisible { close() } else { show() }
    }

    func close() { panel.orderOut(nil) }

    func show() {
        if model.selectedID == nil || store.note(model.selectedID!) == nil {
            if let first = store.notes.first { model.selectedID = first.id } else { model.newNote() }
        }
        let size = panel.frame.size
        var origin = NSPoint(x: 100, y: 100)
        if let button = item?.button, let window = button.window {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.minY - 4 - size.height)
            let area = (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero
            origin.x = max(area.minX + 8, min(origin.x, area.maxX - size.width - 8))
            origin.y = max(area.minY + 8, origin.y)
        }
        panel.setFrameOrigin(origin)
        lastShown = Date()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.panel.contentView,
                  let text = view.firstDescendant(ofType: NoteTextView.self, where: { _ in true }) else { return }
            self?.panel.makeFirstResponder(text)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Le changement d'application en cours d'ouverture ne doit pas refermer aussitôt le volet.
        guard panel.isVisible, Date().timeIntervalSince(lastShown) > 0.3 else { return }
        close()
    }

    func windowDidEndLiveResize(_ notification: Notification) { saveSize() }

    // Poignée du coin : le coin haut-gauche reste en place, la souris (coordonnées écran) donne la nouvelle taille.
    private func beginResize() { resizeStart = (NSEvent.mouseLocation, panel.frame) }

    private func resize() {
        guard let start = resizeStart else { return }
        let now = NSEvent.mouseLocation
        let width = max(Self.minSize.width, min(panel.maxSize.width, start.frame.width + now.x - start.mouse.x))
        let height = max(Self.minSize.height, min(panel.maxSize.height, start.frame.height - (now.y - start.mouse.y)))
        panel.setFrame(NSRect(x: start.frame.minX, y: start.frame.maxY - height, width: width, height: height), display: true)
        if NSEvent.pressedMouseButtons == 0 { saveSize(); resizeStart = nil }
    }

    private func showMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        add(L("menubar.open"), #selector(menuOpen))
        add(L("note.new"), #selector(menuNew))
        add(L("menu.settings"), #selector(menuSettings))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        item?.menu = menu
        item?.button?.performClick(nil)
        item?.menu = nil   // sans cela le clic gauche ouvrirait aussi le menu
    }

    @objc private func menuOpen() { openApp() }
    @objc private func menuNew() { model.newNote(); show() }
    @objc private func menuSettings() { openSettings() }
}

// MARK: Volet

private let dotColors: [Color] = RichText.palette.map { Color(hex: $0) }

struct QuickView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: NoteStore
    var openApp: () -> Void = {}
    var beginResize: () -> Void = {}
    var resize: () -> Void = {}
    @State private var resizing = false
    @State private var selection = ""
    @AppStorage(Prefs.fontSize) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.fontFamily) private var fontFamily = ""
    @AppStorage(Prefs.dotNumbers) private var dotNumbers = false

    /// Les pastilles suivent l'ordre de création : une note garde sa couleur, quelles que soient ses modifications.
    private var dotNotes: [Note] {
        Array(store.notes.sorted { ($0.created, $0.id.uuidString) < ($1.created, $1.id.uuidString) }.prefix(dotColors.count))
    }

    var body: some View {
        let note = model.selectedID.flatMap { store.note($0) }
        VStack(spacing: 0) {
            HStack(spacing: Socle.M.space2) {
                ForEach(Array(dotNotes.enumerated()), id: \.element.id) { index, entry in
                    Dot(color: dotColors[index], number: dotNumbers ? index + 1 : nil, selected: entry.id == model.selectedID,
                        title: entry.title.isEmpty ? L("note.untitled") : entry.title)
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
                NoteEditor(noteID: note.id, text: note.text, rtf: note.rtf, fontSize: fontSize, fontFamily: fontFamily,
                           onChange: { store.update(id: note.id, text: $0, rtf: $1) },
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
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10))
                    .foregroundStyle(Socle.C.textSubtle).frame(width: 22, height: 22).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.crosshair.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { _ in if !resizing { resizing = true; beginResize() }; resize() }
                        .onEnded { _ in resizing = false; resize() })
                    .help(L("menubar.resize"))
            }
            .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space1_5)
            .background(Socle.C.surfaceRaised)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Socle.C.surface)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Socle.C.borderStrong, lineWidth: 1))
    }
}

private struct Dot: View {
    let color: Color
    let number: Int?
    let selected: Bool
    let title: String

    var body: some View {
        let size: CGFloat = number == nil ? 14 : 18
        Circle().fill(color).frame(width: size, height: size)
            .overlay {
                if let number { Text("\(number)").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.black.opacity(0.8)) }
            }
            .overlay(Circle().stroke(Socle.C.textStrong, lineWidth: selected ? 2 : 0).padding(-3))
            .frame(width: 24, height: 24)
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
