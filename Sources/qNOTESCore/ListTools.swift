import Foundation

/// Puces intelligentes : reconnaissance d'une ligne de liste et suite automatique à « Retour ».
public enum ListTools {
    /// Puces proposées dans les réglages ; toutes sont reconnues à la frappe, quelle que soit celle choisie.
    public static let bulletGlyphs: [String] = ["-", "•", "▸", "–", "→", "◦"]
    static let bulletSet: Set<Character> = ["-", "*", "+", "•", "▸", "–", "→", "◦"]

    public enum Kind: Equatable, Sendable {
        case bullet(Character)
        case check(Character, done: Bool)
        case number(Int, separator: Character)
    }

    public struct Item: Equatable, Sendable {
        public var indent: String
        public var kind: Kind
        /// Nombre de caractères de la ligne occupés par l'indentation et le marqueur (espace suivant compris).
        public var markerLength: Int
        public var content: String
        /// Plage (en caractères de la ligne) de la case « [ ] » d'une tâche.
        public var checkboxRange: Range<Int>?
    }

    public static func parse(_ line: String) -> Item? {
        let chars = Array(line)
        var i = 0
        while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
        let indent = String(chars[0..<i])
        guard i < chars.count else { return nil }
        let c = chars[i]
        if bulletSet.contains(c), i + 1 < chars.count, chars[i + 1] == " " {
            var j = i + 2
            // Tâche : « [ ] » ou « [x] » juste après la puce.
            if j + 2 < chars.count, chars[j] == "[", chars[j + 2] == "]", " xX".contains(chars[j + 1]),
               j + 3 == chars.count || chars[j + 3] == " " {
                let done = chars[j + 1] != " "
                let boxStart = j
                j += 3
                if j < chars.count { j += 1 }
                return Item(indent: indent, kind: .check(c, done: done), markerLength: j,
                            content: String(chars[min(j, chars.count)...]), checkboxRange: boxStart..<(boxStart + 3))
            }
            return Item(indent: indent, kind: .bullet(c), markerLength: i + 2, content: String(chars[(i + 2)...]), checkboxRange: nil)
        }
        if c.isNumber {
            var j = i
            while j < chars.count, chars[j].isASCII, chars[j].isNumber { j += 1 }
            if j > i, j < chars.count - 0, j + 1 < chars.count, chars[j] == "." || chars[j] == ")", chars[j + 1] == " ",
               let n = Int(String(chars[i..<j])) {
                return Item(indent: indent, kind: .number(n, separator: chars[j]), markerLength: j + 2,
                            content: String(chars[(j + 2)...]), checkboxRange: nil)
            }
        }
        return nil
    }

    public enum ReturnAction: Equatable, Sendable {
        case none
        /// Texte à insérer à la place du retour à la ligne (commence par « \n »).
        case insert(String)
        /// Puce vide : on la supprime et on sort de la liste (nombre de caractères à retirer du début de la ligne).
        case endList(Int)
    }

    /// Que faire quand l'utilisateur appuie sur Retour avec le curseur à la fin de `line` ?
    public static func onReturn(line: String, glyph: String = "-") -> ReturnAction {
        guard let item = parse(line) else { return .none }
        if item.content.trimmingCharacters(in: .whitespaces).isEmpty { return .endList(item.markerLength) }
        return .insert("\n" + item.indent + nextMarker(item, glyph: glyph))
    }

    static func nextMarker(_ item: Item, glyph: String) -> String {
        switch item.kind {
        case .bullet(let c): return String(c) + " "
        case .check(let c, _): return String(c) + " [ ] "
        case .number(let n, let sep): return "\(n + 1)\(sep) "
        }
    }

    /// Frappe d'une espace après « - », « * » ou « + » en début de ligne : la puce choisie dans les réglages la remplace.
    /// `beforeCursor` : texte de la ligne avant le curseur. Renvoie la chaîne qui doit le remplacer, ou nil.
    public static func bulletSubstitution(beforeCursor: String, glyph: String) -> String? {
        let trimmed = beforeCursor.drop(while: { $0 == " " || $0 == "\t" })
        let indent = beforeCursor.prefix(beforeCursor.count - trimmed.count)
        if trimmed == "-" || trimmed == "*" || trimmed == "+" {
            return glyph == String(trimmed) ? nil : String(indent) + glyph + " "
        }
        if trimmed == "[]" || trimmed == "[ ]" { return String(indent) + glyph + " [ ] " }
        return nil
    }

    /// Bascule la case d'une tâche : renvoie la ligne modifiée.
    public static func toggled(_ line: String) -> String? {
        guard let item = parse(line), case .check(_, let done) = item.kind, let box = item.checkboxRange else { return nil }
        var chars = Array(line)
        chars[box.lowerBound + 1] = done ? " " : "x"
        return String(chars)
    }

    public static func indented(_ line: String) -> String { "  " + line }

    public static func outdented(_ line: String) -> String {
        if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("\t") || line.hasPrefix(" ") { return String(line.dropFirst(1)) }
        return line
    }
}

/// Séparateurs personnalisables : « --- » + Retour devient le séparateur choisi.
public enum Separators {
    public static let presets: [String] = [
        "────────────────────",
        "— — — — — —",
        "• • •",
        "⁂",
        "***",
        "========================",
    ]

    /// Une ligne « --- », « *** » ou « ___ » (3 caractères ou plus, tous identiques) déclenche le remplacement.
    public static func isTrigger(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3, let first = t.first, "-*_".contains(first) else { return false }
        return t.allSatisfy { $0 == first }
    }

    /// Une ligne qui n'est faite que du séparateur choisi (ou d'un des préréglages) : elle est dessinée en discret.
    public static func isSeparatorLine(_ line: String, custom: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        return t == custom.trimmingCharacters(in: .whitespaces) || presets.contains(t)
    }
}
