import Combine
import Foundation
import WidgetKit
import qNOTESCore

/// Envoie au widget un résumé des notes (fichier JSON du groupe d'applications) et lui demande de se redessiner.
@MainActor
final class WidgetBridge {
    private var subscription: AnyCancellable?

    init(store: NoteStore) {
        subscription = store.$notes
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { notes in
                if WidgetShare.write(WidgetShare.snapshot(from: notes)) { WidgetCenter.shared.reloadAllTimelines() }
            }
    }
}
