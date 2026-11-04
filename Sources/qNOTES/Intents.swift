import AppIntents
import AppKit
import qNOTESCore

/// Actions Raccourcis de qNOTES : créer une note, ajouter du texte à une note, lire le texte d'une note.
/// Elles travaillent sur le même magasin que la fenêtre ; l'appli reste en arrière-plan.

@MainActor
private var intentStore: NoteStore {
    (NSApp.delegate as? AppDelegate)?.store ?? NoteStore(directory: NoteStore.localDirectory)
}

struct NoteEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Note"
    static let defaultQuery = NoteEntityQuery()

    var id: UUID
    var title: String
    var text: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title.isEmpty ? L("note.untitled") : title)")
    }

    init(_ note: Note) {
        id = note.id
        title = note.title
        text = note.text
    }
}

struct NoteEntityQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [NoteEntity] {
        identifiers.compactMap { intentStore.note($0) }.map(NoteEntity.init)
    }

    @MainActor func entities(matching string: String) async throws -> [NoteEntity] {
        intentStore.notes.filter { $0.text.localizedCaseInsensitiveContains(string) }.map(NoteEntity.init)
    }

    @MainActor func suggestedEntities() async throws -> [NoteEntity] {
        intentStore.notes.prefix(30).map(NoteEntity.init)
    }
}

struct CreateNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Note"
    static let description = IntentDescription("Creates a qNOTES note with the given text.")

    @Parameter(title: "Text") var text: String

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<NoteEntity> {
        let store = intentStore
        let note = store.create(text: text)
        store.flush()
        return .result(value: NoteEntity(note))
    }
}

struct AppendToNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Text to Note"
    static let description = IntentDescription("Adds text at the end of a qNOTES note.")

    @Parameter(title: "Note") var note: NoteEntity
    @Parameter(title: "Text") var text: String

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<NoteEntity> {
        let store = intentStore
        store.append(id: note.id, text: text)
        store.flush()
        guard let updated = store.note(note.id) else { throw $note.needsValueError() }
        return .result(value: NoteEntity(updated))
    }
}

struct GetNoteTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Note Text"
    static let description = IntentDescription("Returns the text of a qNOTES note.")

    @Parameter(title: "Note") var note: NoteEntity

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let current = intentStore.note(note.id) else { throw $note.needsValueError() }
        return .result(value: current.text)
    }
}
