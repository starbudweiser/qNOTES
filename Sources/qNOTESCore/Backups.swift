import Foundation

/// Sauvegardes automatiques : un fichier `backup-AAAAMMJJ-HHMMSS.json` contenant toutes les notes.
public struct BackupInfo: Identifiable, Equatable, Sendable {
    public var url: URL
    public var date: Date
    public var noteCount: Int
    public var id: URL { url }
}

public enum Backups {
    struct Archive: Codable {
        var version: Int
        var date: Date
        var notes: [Note]
    }

    public static var defaultDirectory: URL { NoteStore.supportDirectory.appendingPathComponent("Backups") }

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

    private static func name(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "backup-\(f.string(from: date)).json"
    }

    /// Écrit une sauvegarde de `notes`. Ne fait rien si la liste est vide.
    @discardableResult
    public static func create(notes: [Note], in directory: URL = defaultDirectory, date: Date = Date()) throws -> URL? {
        guard !notes.isEmpty else { return nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name(for: date))
        try encoder.encode(Archive(version: 1, date: date, notes: notes)).write(to: url, options: .atomic)
        return url
    }

    /// Sauvegardes présentes, la plus récente d'abord.
    public static func list(in directory: URL = defaultDirectory) -> [BackupInfo] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix("backup-") && $0.pathExtension == "json" }
            .compactMap { url -> BackupInfo? in
                guard let data = try? Data(contentsOf: url), let archive = try? decoder.decode(Archive.self, from: data) else { return nil }
                return BackupInfo(url: url, date: archive.date, noteCount: archive.notes.count)
            }
            .sorted { $0.date > $1.date }
    }

    public static func load(_ url: URL) -> [Note]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Archive.self, from: data).notes
    }

    /// Ne garde que les `keep` sauvegardes les plus récentes.
    public static func prune(in directory: URL = defaultDirectory, keep: Int) {
        for info in list(in: directory).dropFirst(max(1, keep)) { try? FileManager.default.removeItem(at: info.url) }
    }

    /// Date de la dernière sauvegarde, pour savoir si une nouvelle est due.
    public static func lastDate(in directory: URL = defaultDirectory) -> Date? { list(in: directory).first?.date }
}
