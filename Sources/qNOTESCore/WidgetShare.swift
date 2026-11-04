import Foundation

/// Note résumée pour le widget : titre et quelques lignes de texte nettoyées de leurs balises Markdown.
public struct WidgetNote: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var lines: [String]
    public var modified: Date
    public var pinned: Bool

    public init(id: UUID, title: String, lines: [String], modified: Date, pinned: Bool) {
        self.id = id; self.title = title; self.lines = lines; self.modified = modified; self.pinned = pinned
    }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var date: Date
    public var notes: [WidgetNote]

    public init(date: Date, notes: [WidgetNote]) { self.date = date; self.notes = notes }
}

/// Données partagées entre l'appli et son widget : un fichier JSON dans le conteneur du groupe d'applications.
public enum WidgetShare {
    public static let groupID = "35KLMK53PN.fr.stephan.qnotes"
    public static let fileName = "widget.json"
    public static let urlScheme = "qnotes"

    /// Dossier partagé. Hors bac à sable (l'appli), le chemin est celui du dossier Group Containers ; dans le widget
    /// (bac à sable), le système donne le conteneur du groupe. `QNOTES_WIDGET_DIR` redirige pour les essais.
    public static var directory: URL {
        if let custom = ProcessInfo.processInfo.environment["QNOTES_WIDGET_DIR"], !custom.isEmpty { return URL(fileURLWithPath: custom) }
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) { return container }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/\(groupID)")
    }

    public static func snapshot(from notes: [Note], limit: Int = 6, now: Date = Date()) -> WidgetSnapshot {
        let items = notes.filter { !$0.title.isEmpty }.prefix(limit).map { note -> WidgetNote in
            var lines: [String] = []
            var seenTitle = false
            for raw in note.text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let s = Note.plain(raw) else { continue }
                if !seenTitle { seenTitle = true; continue }
                lines.append(String(s.prefix(120)))
                if lines.count >= 8 { break }
            }
            return WidgetNote(id: note.id, title: note.title, lines: lines, modified: Date(timeIntervalSince1970: note.modified.timeIntervalSince1970.rounded(.down)), pinned: note.pinned)
        }
        return WidgetSnapshot(date: now, notes: Array(items))
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Écrit l'instantané ; renvoie false s'il n'a pas changé (pas besoin de rafraîchir le widget).
    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot, to directory: URL = directory) -> Bool {
        if let old = read(from: directory), old.notes == snapshot.notes { return false }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(snapshot) else { return false }
        return (try? data.write(to: directory.appendingPathComponent(fileName), options: .atomic)) != nil
    }

    public static func read(from directory: URL = directory) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public static func url(for id: UUID) -> URL { URL(string: "\(urlScheme)://note/\(id.uuidString)")! }

    public static func noteID(from url: URL) -> UUID? {
        guard url.scheme == urlScheme, url.host == "note" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
