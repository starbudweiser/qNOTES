import AppKit
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
    @AppStorage(Prefs.bulletGlyph) private var glyph = "-"
    @AppStorage(Prefs.separator) private var separator = Separators.presets[0]
    @AppStorage(Prefs.syncICloud) private var sync = false
    @AppStorage(Prefs.backupEnabled) private var backupOn = true
    @AppStorage(Prefs.backupKeep) private var keep = 30
    @AppStorage(Prefs.backupHours) private var hours = 1
    @AppStorage(Prefs.autoUpdate) private var autoUpdate = true
    @AppStorage(Prefs.displayMode) private var display = "both"
    @AppStorage(Prefs.hotkeyEnabled) private var hotkey = true
    @State private var backups: [BackupInfo] = []
    @State private var toRestore: BackupInfo?
    @State private var notice = ""

    private let cloudAvailable = NoteStore.iCloudDirectory != nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Socle.M.space6) {
                section(L("set.display")) {
                    SocleSegmented(options: Prefs.displayModes, selection: display, label: { L("set.display.\($0)") }) { display = $0 }
                    hint(L("set.display.hint"))
                    toggle(L("set.hotkey"), $hotkey)
                }
                section(L("set.writing")) {
                    row(L("set.fontsize")) {
                        SocleSegmented(options: [14.0, 16.0, 18.0, 20.0], selection: fontSize, label: { "\(Int($0))" }) { fontSize = $0 }
                    }
                }
                section(L("set.lists")) {
                    toggle(L("set.smart"), $smart)
                    row(L("set.bullet")) {
                        SocleSegmented(options: ListTools.bulletGlyphs, selection: glyph, label: { $0 }) { glyph = $0 }
                    }
                    hint(L("set.bullet.hint"))
                }
                section(L("set.separator")) {
                    SocleSegmented(options: Separators.presets, selection: separator, label: { String($0.prefix(7)) }) { separator = $0 }
                    TextField(L("set.separator.custom"), text: $separator).socleField()
                    hint(L("set.separator.hint"))
                }
                section(L("set.sync")) {
                    toggle(L("set.sync.icloud"), $sync, disabled: !cloudAvailable)
                    hint(cloudAvailable ? L("set.sync.hint") : L("set.sync.unavailable"))
                }
                section(L("set.backups")) {
                    toggle(L("set.backups.on"), $backupOn)
                    row(L("set.backups.every")) {
                        SocleSegmented(options: [1, 6, 24], selection: hours, label: { L("set.hours", $0) }) { hours = $0 }
                    }
                    row(L("set.backups.keep")) {
                        SocleSegmented(options: [10, 30, 100], selection: keep, label: { "\($0)" }) { keep = $0 }
                    }
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
                            ForEach(backups.prefix(6)) { info in
                                HStack {
                                    Text(info.date.formatted(date: .abbreviated, time: .shortened)).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                                    Text(L("set.backups.notes", info.noteCount)).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                                    Spacer()
                                    Button(L("set.backups.restore")) { toRestore = info }
                                        .buttonStyle(SocleButtonStyle(.tertiary, height: 26)).fixedSize()
                                }
                                .padding(.vertical, 2)
                                Rectangle().fill(Socle.C.borderSubtle).frame(height: 1)
                            }
                        }
                    }
                }
                section(L("set.updates")) {
                    toggle(L("set.autoupdate"), $autoUpdate)
                    Button(Updater.text("menu", lang: UpdateEngine.shared.currentLang)) { actions.checkUpdates() }
                        .buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
                }
            }
            .padding(Socle.M.space6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 560, height: 640)
        .background(Socle.C.surface)
        .onAppear { backups = Backups.list() }
        .onChange(of: sync) { actions.applySync() }
        .confirmationDialog(L("restore.title"), isPresented: Binding(get: { toRestore != nil }, set: { if !$0 { toRestore = nil } }), titleVisibility: .visible) {
            Button(L("set.backups.restore"), role: .destructive) {
                if let info = toRestore { notice = actions.restore(info.url) ? L("restore.done") : L("restore.failed"); backups = Backups.list() }
                toRestore = nil
            }
            Button(L("common.cancel"), role: .cancel) { toRestore = nil }
        } message: { Text(L("restore.message")) }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Socle.M.space2_5) {
            Text(title.uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
            content()
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
        Toggle(label, isOn: binding).toggleStyle(.checkbox).socle(Socle.T.body).disabled(disabled)
    }

    private func hint(_ text: String) -> some View {
        Text(text).socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle).fixedSize(horizontal: false, vertical: true)
    }
}
