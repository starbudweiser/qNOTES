import Foundation

/// Import de notes : sauvegardes JSON de Tot (The Iconfactory) et fichiers texte ou Markdown.
/// Les données de Tot ne sont jamais modifiées : on ne fait que les lire.
public enum Importer {
    public struct Report: Equatable, Sendable {
        public var added = 0
        public var alreadyPresent = 0
        public var firstID: UUID?
    }

    public enum ImportError: Error { case unreadable, noNotes }

    /// Dossier où Tot écrit ses sauvegardes automatiques (`QNOTES_TOT_DIR` pour les essais).
    nonisolated public static var totBackupsDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["QNOTES_TOT_DIR"], !custom.isEmpty { return URL(fileURLWithPath: custom) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.iconfactory.Tot/Data/Library/Application Support/Tot/Backups")
    }

    /// Sauvegarde la plus récente de Tot (les noms sont des dates : « 2026-11-04 1037.json »).
    nonisolated public static func latestTotBackup() -> URL? {
        let urls = (try? FileManager.default.contentsOfDirectory(at: totBackupsDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first { (try? Data(contentsOf: $0)).flatMap(parseTot) != nil }
    }

    nonisolated private static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    /// Sauvegarde Tot : `{"tot_backup": "1.0", "dots": [{"text": …, "date": …}, …]}`. Les points vides sont ignorés.
    nonisolated public static func parseTot(_ data: Data) -> [Note]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["tot_backup"] != nil, let dots = root["dots"] as? [[String: Any]] else { return nil }
        return dots.compactMap { dot -> Note? in
            guard let text = dot["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let date = parseDate(dot["date"] as? String) ?? Date()
            return Note(text: text, created: date, modified: date)
        }
    }

    /// Notes d'un fichier : sauvegarde Tot (.json) ou texte / Markdown (une note par fichier).
    nonisolated public static func notes(from url: URL) throws -> [Note] {
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        if url.pathExtension.lowercased() == "json" {
            guard let notes = parseTot(data), !notes.isEmpty else { throw ImportError.noNotes }
            return notes
        }
        guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.noNotes
        }
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        return [Note(text: text, created: date, modified: date)]
    }

    /// Ajoute les notes au magasin, avec leurs dates d'origine. Une note dont le texte existe déjà n'est pas ajoutée deux fois.
    @MainActor
    public static func add(_ notes: [Note], to store: NoteStore) -> Report {
        var report = Report()
        var known = Set(store.notes.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) })
        for note in notes.sorted(by: { $0.modified < $1.modified }) {
            let key = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if known.contains(key) { report.alreadyPresent += 1; continue }
            known.insert(key)
            var fresh = note
            fresh.id = UUID()
            store.insert(fresh)
            report.added += 1
            report.firstID = fresh.id
        }
        store.flush()
        return report
    }
}
