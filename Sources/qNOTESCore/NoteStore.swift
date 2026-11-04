import Combine
import Foundation

/// Stockage des notes : un fichier `<id>.json` par note dans `directory`. Le dossier peut être dans iCloud Drive
/// (synchronisation) : `reload()` relit les changements venus d'ailleurs, la version la plus récente gagne.
@MainActor
public final class NoteStore: ObservableObject {
    /// Épinglées d'abord, puis la plus récemment modifiée.
    @Published public private(set) var notes: [Note] = []
    public private(set) var directory: URL

    private var dirty: Set<UUID> = []
    private var writeTimer: Timer?
    private var pollTimer: Timer?
    /// Date de modification des fichiers déjà lus : on ne relit que ce qui a changé.
    private var seen: [String: Date] = [:]
    private var onDisk: Set<UUID> = []

    public init(directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory.resolvingSymlinksInPath()  // contentsOfDirectory(at:) échoue sur un lien symbolique
        reload()
    }

    // MARK: Emplacements

    /// Dossier local par défaut (`QNOTES_DATA_DIR` pour les essais).
    nonisolated public static var localDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["QNOTES_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom).appendingPathComponent("Notes")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("qNOTES/Notes")
    }

    /// Dossier racine de l'appli (réglages, sauvegardes).
    nonisolated public static var supportDirectory: URL { localDirectory.deletingLastPathComponent() }

    /// Dossier qNOTES d'iCloud Drive, ou nil si iCloud Drive n'est pas activé sur ce Mac.
    nonisolated public static var iCloudDirectory: URL? {
        if let custom = ProcessInfo.processInfo.environment["QNOTES_ICLOUD_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        let drive = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: drive.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return drive.appendingPathComponent("qNOTES")
    }

    // MARK: Lecture

    public func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private func fileURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).json") }

    /// Relit le dossier : notes nouvelles ou modifiées ailleurs, notes supprimées ailleurs.
    public func reload() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
                                                options: [])) ?? []
        var byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        var present: Set<UUID> = []
        var changed = false

        for url in urls {
            let name = url.lastPathComponent
            // Fichier iCloud pas encore téléchargé (« .nom.json.icloud ») : on demande le téléchargement.
            if name.hasPrefix("."), name.hasSuffix(".json.icloud") {
                try? fm.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard url.pathExtension == "json" else { continue }
            let stamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if seen[name] == stamp, let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) {
                present.insert(id)
                continue
            }
            guard let data = try? Data(contentsOf: url), let note = try? Self.decoder.decode(Note.self, from: data) else { continue }
            seen[name] = stamp
            present.insert(note.id)
            // Comparaison par nom de fichier, jamais par chemin : un dossier derrière un lien symbolique (/tmp, volume externe)
            // donne deux chemins pour le même fichier, et le supprimer serait une perte de données.
            let canonicalName = "\(note.id.uuidString).json"
            if name != canonicalName {
                // Copie de conflit iCloud (« <id> 2.json ») : la plus récente des deux reste, l'autre est supprimée.
                let canonical = directory.appendingPathComponent(canonicalName)
                if let existing = byID[note.id], existing.modified >= note.modified {
                    try? fm.removeItem(at: url)
                    seen[name] = nil
                    continue
                }
                try? fm.removeItem(at: canonical)
                try? fm.moveItem(at: url, to: canonical)
                seen[name] = nil
                seen[canonicalName] = (try? canonical.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            }
            if let existing = byID[note.id] {
                if note.modified > existing.modified, !dirty.contains(note.id) {
                    byID[note.id] = note
                    changed = true
                }
            } else {
                byID[note.id] = note
                changed = true
            }
        }

        // Fichier disparu alors que la note n'a pas de modification locale en attente : supprimée ailleurs.
        for id in onDisk.subtracting(present) where !dirty.contains(id) {
            byID[id] = nil
            changed = true
        }
        onDisk = present
        if changed { publish(Array(byID.values)) }
    }

    private func publish(_ list: [Note]) {
        notes = list.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.modified > $1.modified
        }
    }

    // MARK: Écriture

    @discardableResult
    public func create(text: String = "") -> Note {
        let note = Note(text: text)
        publish(notes + [note])
        markDirty(note.id)
        return note
    }

    /// Modification du texte : prise en compte tout de suite, écriture disque différée.
    public func update(id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        var list = notes
        list[index].text = text
        list[index].modified = Date()
        publish(list)
        markDirty(id)
    }

    public func setPinned(id: UUID, _ pinned: Bool) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].pinned != pinned else { return }
        var list = notes
        list[index].pinned = pinned
        list[index].modified = Date()
        publish(list)
        markDirty(id)
    }

    public func delete(id: UUID) {
        publish(notes.filter { $0.id != id })
        dirty.remove(id)
        let url = fileURL(id)
        try? FileManager.default.removeItem(at: url)
        seen[url.lastPathComponent] = nil
        onDisk.remove(id)
    }

    /// Ajoute du texte à la fin d'une note (Raccourcis, ligne de commande).
    public func append(id: UUID, text: String) {
        guard let note = note(id) else { return }
        let separator = note.text.isEmpty || note.text.hasSuffix("\n") ? "" : "\n"
        update(id: id, text: note.text + separator + text)
    }

    private func markDirty(_ id: UUID) {
        dirty.insert(id)
        writeTimer?.invalidate()
        writeTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    /// Écrit tout de suite les modifications en attente (avant de quitter, avant une sauvegarde).
    public func flush() {
        writeTimer?.invalidate()
        for id in dirty {
            guard let note = note(id), let data = try? Self.encoder.encode(note) else { continue }
            let url = fileURL(id)
            try? data.write(to: url, options: .atomic)
            seen[url.lastPathComponent] = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            onDisk.insert(id)
        }
        dirty.removeAll()
    }

    // MARK: Veille et changement de dossier

    /// Relit le dossier régulièrement : c'est ce qui fait apparaître les notes venues d'iCloud.
    public func startWatching(interval: TimeInterval = 4) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        pollTimer?.tolerance = 1
    }

    /// Passe à un autre dossier (iCloud Drive ↔ local). Les notes des deux dossiers sont fusionnées : la plus récente gagne.
    public func switchDirectory(to newDirectory: URL) {
        flush()
        try? FileManager.default.createDirectory(at: newDirectory, withIntermediateDirectories: true)
        guard newDirectory.resolvingSymlinksInPath() != directory else { return }
        let current = notes
        directory = newDirectory.resolvingSymlinksInPath()
        seen = [:]
        onDisk = []
        notes = []
        reload()
        var byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        for note in current where (byID[note.id]?.modified ?? .distantPast) < note.modified {
            byID[note.id] = note
            dirty.insert(note.id)
        }
        // Les notes du dossier précédent absentes du nouveau y sont recopiées.
        for note in current where byID[note.id] == nil { byID[note.id] = note; dirty.insert(note.id) }
        publish(Array(byID.values))
        flush()
    }

    /// Remplace toutes les notes (restauration d'une sauvegarde).
    public func replaceAll(with newNotes: [Note]) {
        flush()
        for note in notes where !newNotes.contains(where: { $0.id == note.id }) { delete(id: note.id) }
        publish(newNotes)
        for note in newNotes { dirty.insert(note.id) }
        flush()
    }
}
