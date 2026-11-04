import Foundation
import SwiftUI
import qNOTESCore

/// État de l'interface : note ouverte et recherche.
@MainActor
final class AppModel: ObservableObject {
    @Published var selectedID: UUID?
    @Published var query = ""
    @Published var pendingDelete: UUID?
    let store: NoteStore

    init(store: NoteStore) {
        self.store = store
        selectedID = store.notes.first?.id
    }

    var filtered: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.notes }
        return store.notes.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    func newNote() {
        // Une note vide déjà ouverte est réutilisée plutôt que d'en empiler.
        if let id = selectedID, let n = store.note(id), n.text.isEmpty { return }
        query = ""
        selectedID = store.create().id
    }

    func delete(_ id: UUID) {
        let list = filtered
        let index = list.firstIndex { $0.id == id }
        store.delete(id: id)
        let remaining = filtered
        if selectedID == id {
            selectedID = index.flatMap { remaining.indices.contains($0) ? remaining[$0].id : remaining.last?.id } ?? remaining.last?.id
        }
    }

    func requestDelete(_ id: UUID) {
        if store.note(id)?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true { delete(id) } else { pendingDelete = id }
    }

    func duplicate(_ id: UUID) {
        guard let n = store.note(id) else { return }
        selectedID = store.create(text: n.text).id
    }
}
