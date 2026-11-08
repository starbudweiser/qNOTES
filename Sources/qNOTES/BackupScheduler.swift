import Foundation
import qNOTESCore

/// Sauvegardes automatiques : au lancement puis toutes les dix minutes, dès que la dernière a plus d'un jour.
@MainActor
final class BackupScheduler {
    private let store: NoteStore
    private var timer: Timer?

    init(store: NoteStore) { self.store = store }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runIfDue() }
        }
        timer?.tolerance = 60
        runIfDue()
    }

    func runIfDue() {
        guard Prefs.backups else { return }
        let last = Backups.lastDate() ?? .distantPast
        guard Date().timeIntervalSince(last) >= Double(Prefs.backupEveryHours) * 3600 else { return }
        backupNow()
    }

    @discardableResult
    func backupNow() -> Bool {
        store.flush()
        let made = (try? Backups.create(notes: store.notes)) ?? nil
        Backups.prune(keep: Prefs.backupKept)
        return made != nil
    }

    /// Restaure une sauvegarde. L'état actuel est d'abord sauvegardé, pour pouvoir revenir en arrière.
    func restore(_ url: URL) -> Bool {
        guard let notes = Backups.load(url) else { return false }
        backupNow()
        store.replaceAll(with: notes)
        return true
    }
}
