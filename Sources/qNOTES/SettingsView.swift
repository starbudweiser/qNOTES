import AppKit
import ServiceManagement
import SwiftUI
import qNOTESCore

@MainActor
struct SettingsActions {
    var applySync: () -> Void
    var backupNow: () -> Bool
    var restore: (URL) -> Bool
    var checkUpdates: () -> Void
}

struct SettingsView: View {
    let actions: SettingsActions
    @AppStorage(Prefs.fontSize) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.smartBullets) private var smart = true
    @AppStorage(Prefs.bulletGlyph) private var glyph = "•"
    @AppStorage(Prefs.fontFamily) private var fontFamily = ""
    @AppStorage(Prefs.monospaced) private var mono = false
    @AppStorage(Prefs.translucent) private var translucent = false
    @AppStorage(Prefs.stayOnTop) private var stayOnTop = false
    @AppStorage(Prefs.separator) private var separator = Separators.presets[0]
    @AppStorage(Prefs.syncICloud) private var sync = false
    @AppStorage(Prefs.backupEnabled) private var backupOn = true
    @State private var allBackups = false
    @AppStorage(Prefs.autoUpdate) private var autoUpdate = true
    @AppStorage(Prefs.displayMode) private var display = "both"
    @AppStorage(Prefs.hotkeyEnabled) private var hotkey = true
    @AppStorage(Prefs.dotNumbers) private var dotNumbers = false
    @AppStorage(Prefs.panelMode) private var panelMode = "auto"
    @State private var reducedTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var backups: [BackupInfo] = []
    @State private var toRestore: BackupInfo?
    @State private var notice = ""

    private let cloudAvailable = NoteStore.iCloudDirectory != nil

    @State private var tab = "general"
    private let tabs = ["general", "writing", "data"]

    var body: some View {
        VStack(spacing: 0) {
            SocleSegmented(options: tabs, selection: tab, label: { L("set.tab.\($0)") }) { tab = $0 }
                .padding(.horizontal, Socle.M.space6).padding(.top, Socle.M.space5).padding(.bottom, Socle.M.space4)
            ScrollView {
                VStack(alignment: .leading, spacing: Socle.M.space6) {
                    switch tab {
                    case "writing": writingTab
                    case "data": dataTab
                    default: generalTab
                    }
                }
                .padding(.horizontal, Socle.M.space6).padding(.bottom, Socle.M.space6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 580, height: 600)
        .background(Socle.C.surface)
        .onAppear { backups = Backups.list() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)) { _ in
            reducedTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
        .onChange(of: sync) { actions.applySync() }
        .confirmationDialog(L("restore.title"), isPresented: Binding(get: { toRestore != nil }, set: { if !$0 { toRestore = nil } }), titleVisibility: .visible) {
            Button(L("set.backups.restore"), role: .destructive) {
                if let info = toRestore { notice = actions.restore(info.url) ? L("restore.done") : L("restore.failed"); backups = Backups.list() }
                toRestore = nil
            }
            Button(L("common.cancel"), role: .cancel) { toRestore = nil }
        } message: { Text(L("restore.message")) }
    }

    private var generalTab: some View {
        Group {
            section(L("set.display")) {
                SocleSegmented(options: Prefs.displayModes, selection: display, label: { L("set.display.\($0)") }) { display = $0 }
                hint(L("set.display.hint"))
            }
            section(L("set.panel")) {
                SocleSegmented(options: Prefs.panelModes, selection: panelMode, label: { L("set.panel.\($0)") }) { panelMode = $0 }
                hint(L("set.panel.hint"))
                Divider().overlay(Socle.C.borderSubtle)
                toggle(L("set.dotnumbers"), $dotNumbers)
                toggle(L("set.hotkey"), $hotkey)
            }
            section(L("set.window")) {
                toggle(L("set.translucent"), $translucent)
                if reducedTransparency { hint(L("set.translucent.reduced")) }
                Divider().overlay(Socle.C.borderSubtle)
                toggle(L("set.stayontop"), $stayOnTop)
                Divider().overlay(Socle.C.borderSubtle)
                toggle(L("set.login"), Binding(get: { login }, set: { setLogin($0) }))
            }
        }
    }

    private var writingTab: some View {
        Group {
            section(L("set.writing")) {
                row(L("set.font")) { FontPickerButton(family: $fontFamily).opacity(mono ? 0.45 : 1).disabled(mono) }
                Divider().overlay(Socle.C.borderSubtle)
                toggle(L("set.monospaced"), $mono)
                Divider().overlay(Socle.C.borderSubtle)
                row(L("set.fontsize")) {
                    SocleSegmented(options: [14.0, 16.0, 18.0, 20.0], selection: fontSize, label: { "\(Int($0))" }) { fontSize = $0 }
                        .frame(width: 200)
                }
                Text(L("set.font.sample"))
                    .font(Font(RichText.font(family: mono ? RichText.monoFamily : fontFamily, size: fontSize) as CTFont))
                    .foregroundStyle(Socle.C.text)
                    .padding(Socle.M.space3).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Socle.C.surface, in: RoundedRectangle(cornerRadius: Socle.M.radius))
            }
            section(L("set.lists")) {
                toggle(L("set.smart"), $smart)
                Divider().overlay(Socle.C.borderSubtle)
                row(L("set.bullet")) {
                    SocleSegmented(options: ListTools.bulletGlyphs, selection: glyph, label: { $0 }) { glyph = $0 }
                        .frame(width: 220)
                }
                hint(L("set.bullet.hint"))
            }
            section(L("set.separator")) {
                SocleSegmented(options: Separators.presets, selection: separator, label: { String($0.prefix(7)) }) { separator = $0 }
                TextField(L("set.separator.custom"), text: $separator).socleField()
                hint(L("set.separator.hint"))
            }
        }
    }

    private var dataTab: some View {
        Group {
            section(L("set.sync")) {
                toggle(L("set.sync.icloud"), $sync, disabled: !cloudAvailable)
                hint(cloudAvailable ? L("set.sync.hint") : L("set.sync.unavailable"))
            }
            section(L("set.backups")) {
                toggle(L("set.backups.on"), $backupOn)
                hint(L("set.backups.hint"))
                Divider().overlay(Socle.C.borderSubtle)
                HStack(spacing: Socle.M.space2) {
                    Button(L("set.backups.now")) {
                        notice = actions.backupNow() ? L("set.backups.done") : L("set.backups.nothing")
                        backups = Backups.list()
                    }
                    .buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                    if !notice.isEmpty { Text(notice).socle(Socle.T.meta).foregroundStyle(Socle.C.success) }
                }
                if !backups.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(allBackups ? backups : Array(backups.prefix(1))) { info in
                            HStack {
                                Text(info.date.formatted(date: .abbreviated, time: .shortened)).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                                Text(L("set.backups.notes", info.noteCount)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                                Spacer()
                                Button(L("set.backups.restore")) { toRestore = info }
                                    .buttonStyle(SocleButtonStyle(.tertiary, height: 26)).fixedSize()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    if backups.count > 1 {
                        Button(allBackups ? L("set.backups.less") : L("set.backups.more")) { allBackups.toggle() }
                            .buttonStyle(SocleButtonStyle(.tertiary, height: 26)).fixedSize()
                    }
                }
            }
            section(L("set.updates")) {
                toggle(L("set.autoupdate"), $autoUpdate)
                Divider().overlay(Socle.C.borderSubtle)
                Button(Updater.text("menu", lang: UpdateEngine.shared.currentLang)) { actions.checkUpdates() }
                    .buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
            }
        }
    }

    /// Démarrage à l'ouverture de session (élément de connexion de l'appli, visible dans Réglages Système > Général).
    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("qNOTES: démarrage à l'ouverture de session impossible : \(error)")
        }
        login = SMAppService.mainApp.status == .enabled
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Socle.M.space2_5) {
            Text(title.uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted).padding(.leading, 4)
            VStack(alignment: .leading, spacing: Socle.M.space3) { content() }
                .padding(Socle.M.space4).frame(maxWidth: .infinity, alignment: .leading)
                .background(Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radius))
        }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack {
            Text(label).socle(Socle.T.body).foregroundStyle(Socle.C.text)
            Spacer(minLength: Socle.M.space3)
            content()
        }
    }

    private func toggle(_ label: String, _ binding: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack {
            Text(label).socle(Socle.T.body).foregroundStyle(Socle.C.text)
            Spacer(minLength: Socle.M.space3)
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(disabled)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
    }
}
