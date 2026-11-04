import Foundation

/// Une note : du texte Markdown. Un fichier JSON par note, pour que la synchronisation iCloud Drive
/// ne fusionne jamais deux notes entre elles.
public struct Note: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var created: Date
    public var modified: Date
    public var pinned: Bool

    public init(id: UUID = UUID(), text: String = "", created: Date = Date(), modified: Date = Date(), pinned: Bool = false) {
        self.id = id
        self.text = text
        self.created = created
        self.modified = modified
        self.pinned = pinned
    }

    /// Ligne débarrassée des marqueurs Markdown (puces, #, >, cases, **, __, ~~, `), ou nil si elle ne contient ni lettre ni chiffre
    /// (séparateurs, lignes de « ==== », clôtures de code).
    static func plain(_ raw: Substring) -> String? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard s.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        s = s.replacingOccurrences(of: "</?span[^>]*>", with: "", options: .regularExpression)   // couleur du texte
        while let first = s.first, "#>-*+•▸–→◦_ \t".contains(first) { s.removeFirst() }
        for box in ["[ ]", "[x]", "[X]"] where s.hasPrefix(box) { s = String(s.dropFirst(3)) }
        for mark in ["**", "__", "~~", "`"] { s = s.replacingOccurrences(of: mark, with: "") }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.contains(where: { $0.isLetter || $0.isNumber }) ? s : nil
    }

    /// Première ligne qui dit quelque chose, sans les marqueurs Markdown.
    public var title: String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let s = Self.plain(line) { return String(s.prefix(80)) }
        }
        return ""
    }

    /// Texte qui suit le titre, nettoyé des marqueurs Markdown, sur une ligne, pour la liste.
    public var preview: String {
        var seenTitle = false
        var parts: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let s = Self.plain(raw) else { continue }
            if !seenTitle { seenTitle = true; continue }
            parts.append(s)
            if parts.count >= 4 { break }
        }
        return String(parts.joined(separator: " · ").prefix(140))
    }
}

/// Mots, caractères et lignes d'un texte.
public struct TextCounts: Equatable, Sendable {
    public var words: Int
    public var characters: Int
    public var lines: Int

    public init(_ text: String) {
        var w = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, _, _, _ in w += 1 }
        words = w
        characters = text.count
        lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
    }
}
