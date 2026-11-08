import Foundation

/// Une note : du texte enrichi (RTF) et son miroir en texte simple (`text`, utilisé pour la recherche, le titre, les compteurs,
/// le widget et Raccourcis). Une note sans `rtf` est une ancienne note en Markdown : l'éditeur la convertit à l'ouverture.
/// Un fichier JSON par note, pour que la synchronisation iCloud Drive ne fusionne jamais deux notes entre elles.
public struct Note: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var rtf: Data?
    public var created: Date
    public var modified: Date
    public var pinned: Bool
    /// Place dans la liste (plus petit = plus haut), choisie par l'utilisateur ; les notes épinglées passent d'abord.
    public var order: Double?

    public init(id: UUID = UUID(), text: String = "", rtf: Data? = nil, created: Date = Date(), modified: Date = Date(), pinned: Bool = false, order: Double? = nil) {
        self.id = id
        self.text = text
        self.rtf = rtf
        self.created = created
        self.modified = modified
        self.pinned = pinned
        self.order = order
    }

    /// Ligne débarrassée de ses marqueurs, ou nil si elle ne contient ni lettre ni chiffre (séparateurs, lignes de « ==== »).
    /// `markdown` : ancienne note en Markdown (puces, #, >, cases, **, __, ~~, `, balises de couleur) ; sinon texte enrichi,
    /// où seuls les marqueurs de liste (puce, numéro, case) sont retirés.
    static func plain(_ raw: Substring, markdown: Bool = true) -> String? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard s.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        if !markdown {
            if let item = ListTools.parse(s) { s = item.content.trimmingCharacters(in: .whitespaces) }
            return s.contains(where: { $0.isLetter || $0.isNumber }) ? s : nil
        }
        s = s.replacingOccurrences(of: "</?span[^>]*>", with: "", options: .regularExpression)   // couleur du texte
        while let first = s.first, "#>-*+•▸–→◦_ \t".contains(first) { s.removeFirst() }
        for box in ["[ ]", "[x]", "[X]"] where s.hasPrefix(box) { s = String(s.dropFirst(3)) }
        for mark in ["**", "__", "~~", "`"] { s = s.replacingOccurrences(of: mark, with: "") }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.contains(where: { $0.isLetter || $0.isNumber }) ? s : nil
    }

    /// Première ligne qui dit quelque chose, sans ses marqueurs.
    public var title: String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let s = Self.plain(line, markdown: rtf == nil) { return String(s.prefix(80)) }
        }
        return ""
    }

    /// Texte qui suit le titre, sur une ligne, pour la liste.
    public var preview: String {
        var seenTitle = false
        var parts: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let s = Self.plain(raw, markdown: rtf == nil) else { continue }
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
