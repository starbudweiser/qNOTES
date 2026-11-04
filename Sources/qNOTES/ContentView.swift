import AppKit
import SwiftUI
import qNOTESCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: NoteStore

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, store: store)
                .frame(width: 270)
            Rectangle().fill(Socle.C.border).frame(width: 1)
            Group {
                if let id = model.selectedID, store.note(id) != nil {
                    EditorPane(model: model, store: store, noteID: id)
                } else {
                    EmptyState(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Socle.C.surface)
        }
        .background(Socle.C.bg)
        .confirmationDialog(L("delete.title"), isPresented: Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button(L("delete.confirm"), role: .destructive) {
                if let id = model.pendingDelete { model.delete(id) }
                model.pendingDelete = nil
            }
            Button(L("common.cancel"), role: .cancel) { model.pendingDelete = nil }
        } message: {
            Text(L("delete.message"))
        }
    }
}

private struct EmptyState: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: Socle.M.space3) {
            Text(L("empty.title")).socle(Socle.T.heading).foregroundStyle(Socle.C.textStrong)
            Text(L("empty.body")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted).multilineTextAlignment(.center)
            Button(L("note.new")) { model.newNote() }
                .buttonStyle(SocleButtonStyle(.action))
                .frame(width: 180)
            Button(L("import.button")) { (NSApp.delegate as? AppDelegate)?.importNotes() }
                .buttonStyle(SocleButtonStyle(.secondary))
                .frame(width: 180)
        }
        .padding(Socle.M.space8)
    }
}

// MARK: Barre latérale

private struct Sidebar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: NoteStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Socle.M.space2) {
                TextField(L("search.placeholder"), text: $model.query)
                    .socleField()
                Button { model.newNote() } label: {
                    Image(systemName: "plus").frame(width: 16, height: 16)
                }
                .buttonStyle(SocleButtonStyle(.action))
                .frame(width: Socle.M.sizeControlLg)
                .help(L("note.new"))
            }
            .padding(Socle.M.space3)

            let notes = model.filtered
            if notes.isEmpty {
                Spacer()
                Text(model.query.isEmpty ? L("list.empty") : L("list.noresult"))
                    .socle(Socle.T.body).foregroundStyle(Socle.C.textSubtle)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(notes) { note in
                            NoteRow(note: note, selected: note.id == model.selectedID)
                                .onTapGesture { model.selectedID = note.id }
                                .contextMenu {
                                    Button(note.pinned ? L("note.unpin") : L("note.pin")) { store.setPinned(id: note.id, !note.pinned) }
                                    Button(L("note.duplicate")) { model.duplicate(note.id) }
                                    Button(L("note.copy")) { copy(note) }
                                    Divider()
                                    Button(L("note.delete"), role: .destructive) { model.requestDelete(note.id) }
                                }
                        }
                    }
                    .padding(.horizontal, Socle.M.space2).padding(.bottom, Socle.M.space2)
                }
            }
            Rectangle().fill(Socle.C.border).frame(height: 1)
            Text(L("list.count", store.notes.count))
                .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2)
        }
        .background(Socle.C.surfaceRaised)
    }

    private func copy(_ note: Note) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(RichText.rtf(of: note), forType: .rtf)
        NSPasteboard.general.setString(note.text, forType: .string)
    }
}

private struct NoteRow: View {
    let note: Note
    let selected: Bool
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Socle.M.space1_5) {
                if note.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Socle.C.accentText)
                }
                Text(note.title.isEmpty ? L("note.untitled") : note.title)
                    .socle(Socle.T.labelStrong)
                    .foregroundStyle(note.title.isEmpty ? Socle.C.textSubtle : Socle.C.textStrong)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(Self.dateText(note.modified)).socle(Socle.T.caption).foregroundStyle(Socle.C.textSubtle)
            }
            if !note.preview.isEmpty {
                Text(note.preview).socle(Socle.T.meta).foregroundStyle(Socle.C.textMuted).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space2)
        .background(selected ? Socle.C.surfaceSelected : hover ? Socle.C.surfaceHover : .clear, in: RoundedRectangle(cornerRadius: Socle.M.radius))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    static func dateText(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if cal.isDate(date, equalTo: Date(), toGranularity: .year) { return date.formatted(.dateTime.day().month(.abbreviated)) }
        return date.formatted(.dateTime.day().month(.abbreviated).year(.twoDigits))
    }
}

// MARK: Éditeur

private struct EditorPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: NoteStore
    let noteID: UUID
    @State private var selection = ""
    @AppStorage(Prefs.fontSize) private var fontSize = Prefs.defaultFontSize
    @AppStorage(Prefs.fontFamily) private var fontFamily = ""

    var body: some View {
        let note = store.note(noteID)
        VStack(spacing: 0) {
            FormatBar()
            Rectangle().fill(Socle.C.border).frame(height: 1)
            NoteEditor(noteID: noteID, text: note?.text ?? "", rtf: note?.rtf, fontSize: fontSize, fontFamily: fontFamily,
                       onChange: { store.update(id: noteID, text: $0, rtf: $1) },
                       onSelection: { selection = $0 })
            Rectangle().fill(Socle.C.border).frame(height: 1)
            HStack(spacing: Socle.M.space3) {
                let counts = TextCounts(selection.isEmpty ? (note?.text ?? "") : selection)
                Text((selection.isEmpty ? "" : L("count.selection") + " · ")
                     + L("count.words", counts.words) + " · " + L("count.chars", counts.characters))
                    .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                Spacer()
                if let note {
                    Text(L("note.modified", note.modified.formatted(date: .abbreviated, time: .shortened)))
                        .socle(Socle.T.meta).foregroundStyle(Socle.C.textSubtle)
                }
            }
            .padding(.horizontal, Socle.M.space4).padding(.vertical, Socle.M.space2)
            .background(Socle.C.surfaceRaised)
        }
    }
}
