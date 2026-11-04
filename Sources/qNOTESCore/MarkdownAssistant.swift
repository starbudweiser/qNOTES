import Foundation

/// Mises en forme proposées par l'assistant Markdown (barre d'outils, menu Format, aide).
public enum MarkdownAction: String, CaseIterable, Sendable {
    case h1, h2, h3, bold, italic, strike, code, link, bullet, numbered, task, quote, codeBlock, separator
}

/// Remplacement à appliquer au texte : plage (UTF-16, comme NSRange), nouveau texte, sélection qui en résulte.
public struct TextEdit: Equatable, Sendable {
    public var range: NSRange
    public var replacement: String
    public var selection: NSRange
}

/// Calcule la modification de texte d'une action Markdown. Aucune dépendance à l'interface : testable.
/// Les actions s'inversent d'elles-mêmes : gras sur du texte déjà en gras retire le gras, etc.
public enum MarkdownAssistant {
    public struct Context: Sendable {
        public var glyph = "-"
        public var separator = "────────────────────"
        public var textPlaceholder = "text"
        public var urlPlaceholder = "url"
        public init(glyph: String = "-", separator: String = "────────────────────", textPlaceholder: String = "text", urlPlaceholder: String = "url") {
            self.glyph = glyph
            self.separator = separator
            self.textPlaceholder = textPlaceholder
            self.urlPlaceholder = urlPlaceholder
        }
    }

    public static func edit(_ action: MarkdownAction, in text: String, selection: NSRange, context: Context = Context()) -> TextEdit {
        let ns = text as NSString
        let sel = NSRange(location: min(selection.location, ns.length), length: min(selection.length, ns.length - min(selection.location, ns.length)))
        switch action {
        case .bold: return inline("**", ns, sel, context.textPlaceholder)
        case .italic: return inline("*", ns, sel, context.textPlaceholder)
        case .strike: return inline("~~", ns, sel, context.textPlaceholder)
        case .code: return inline("`", ns, sel, context.textPlaceholder)
        case .link: return link(ns, sel, context)
        case .h1, .h2, .h3, .bullet, .numbered, .task, .quote: return lines(action, ns, sel, context)
        case .codeBlock: return codeBlock(ns, sel)
        case .separator: return separator(ns, sel, context)
        }
    }

    // MARK: En ligne : gras, italique, barré, code

    private static func starRun(_ ns: NSString, from: Int, step: Int) -> Int {
        var n = 0, i = from
        while i >= 0, i < ns.length, ns.character(at: i) == 42 { n += 1; i += step }
        return n
    }

    private static func inline(_ marker: String, _ ns: NSString, _ sel: NSRange, _ placeholder: String) -> TextEdit {
        let ml = (marker as NSString).length
        let single = marker == "*"   // « * » seul : ne pas confondre avec le gras « ** »
        if sel.length == 0 {
            let rep = marker + placeholder + marker
            return TextEdit(range: sel, replacement: rep, selection: NSRange(location: sel.location + ml, length: (placeholder as NSString).length))
        }
        let selected = ns.substring(with: sel)
        let lead = selected.prefix(while: { $0 == "*" }).count, trail = String(selected.reversed()).prefix(while: { $0 == "*" }).count
        let wrappedInside = selected.hasPrefix(marker) && selected.hasSuffix(marker) && sel.length >= 2 * ml + 1
            && (!single || (lead % 2 == 1 && trail % 2 == 1))
        if wrappedInside {
            let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            return TextEdit(range: sel, replacement: inner, selection: NSRange(location: sel.location, length: (inner as NSString).length))
        }
        let beforeOK = sel.location >= ml && ns.substring(with: NSRange(location: sel.location - ml, length: ml)) == marker
        let afterOK = sel.upperBound + ml <= ns.length && ns.substring(with: NSRange(location: sel.upperBound, length: ml)) == marker
        let oddAround = !single || (starRun(ns, from: sel.location - 1, step: -1) % 2 == 1 && starRun(ns, from: sel.upperBound, step: 1) % 2 == 1)
        if beforeOK, afterOK, oddAround {
            return TextEdit(range: NSRange(location: sel.location - ml, length: sel.length + 2 * ml), replacement: selected,
                            selection: NSRange(location: sel.location - ml, length: sel.length))
        }
        return TextEdit(range: sel, replacement: marker + selected + marker, selection: NSRange(location: sel.location + ml, length: sel.length))
    }

    private static func link(_ ns: NSString, _ sel: NSRange, _ ctx: Context) -> TextEdit {
        let label = sel.length > 0 ? ns.substring(with: sel) : ctx.textPlaceholder
        let url = ctx.urlPlaceholder
        let rep = "[\(label)](\(url))"
        // L'adresse est sélectionnée pour être remplacée tout de suite ; sans sélection, c'est le texte du lien.
        if sel.length > 0 {
            return TextEdit(range: sel, replacement: rep, selection: NSRange(location: sel.location + (label as NSString).length + 3, length: (url as NSString).length))
        }
        return TextEdit(range: sel, replacement: rep, selection: NSRange(location: sel.location + 1, length: (label as NSString).length))
    }

    // MARK: Lignes : titres, listes, citation

    private static func blockParts(_ line: String) -> (indent: String, content: String) {
        if let item = ListTools.parse(line) { return (item.indent, item.content) }
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        var rest = String(line.dropFirst(indent.count))
        if rest.hasPrefix("#") {
            let hashes = rest.prefix(while: { $0 == "#" })
            let after = rest.dropFirst(hashes.count)
            if hashes.count <= 6, after.hasPrefix(" ") { rest = String(after.dropFirst()) }
        }
        return (indent, rest)
    }

    private static func headingLevel(_ line: String) -> Int {
        let hashes = line.prefix(while: { $0 == "#" }).count
        return hashes >= 1 && hashes <= 6 && line.dropFirst(hashes).hasPrefix(" ") ? hashes : 0
    }

    private static func lines(_ action: MarkdownAction, _ ns: NSString, _ sel: NSRange, _ ctx: Context) -> TextEdit {
        let para = ns.paragraphRange(for: sel)
        var block = ns.substring(with: para)
        let trailing = block.hasSuffix("\n")
        if trailing { block.removeLast() }
        let source = block.components(separatedBy: "\n")
        let filled = source.indices.filter { !source[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        let targets = filled.isEmpty ? Array(source.indices) : filled   // une seule ligne vide : on y pose le marqueur

        let already: Bool
        switch action {
        case .h1: already = targets.allSatisfy { headingLevel(source[$0]) == 1 }
        case .h2: already = targets.allSatisfy { headingLevel(source[$0]) == 2 }
        case .h3: already = targets.allSatisfy { headingLevel(source[$0]) == 3 }
        case .bullet: already = targets.allSatisfy { if case .bullet? = ListTools.parse(source[$0])?.kind { true } else { false } }
        case .numbered: already = targets.allSatisfy { if case .number? = ListTools.parse(source[$0])?.kind { true } else { false } }
        case .task: already = targets.allSatisfy { if case .check? = ListTools.parse(source[$0])?.kind { true } else { false } }
        case .quote: already = targets.allSatisfy { source[$0].hasPrefix("> ") || source[$0] == ">" }
        default: already = false
        }

        var out = source
        var number = 1
        for index in targets {
            let line = source[index]
            if action == .quote {
                out[index] = already ? String(line.dropFirst(line.hasPrefix("> ") ? 2 : 1)) : "> " + line
                continue
            }
            let (indent, content) = blockParts(line)
            if already { out[index] = indent + content; continue }
            switch action {
            case .h1: out[index] = "# " + content
            case .h2: out[index] = "## " + content
            case .h3: out[index] = "### " + content
            case .bullet: out[index] = indent + ctx.glyph + " " + content
            case .numbered: out[index] = indent + "\(number). " + content; number += 1
            case .task: out[index] = indent + ctx.glyph + " [ ] " + content
            default: break
            }
        }
        let joined = out.joined(separator: "\n")
        let replacement = joined + (trailing ? "\n" : "")
        let length = (joined as NSString).length
        let selection = sel.length == 0 ? NSRange(location: para.location + length, length: 0) : NSRange(location: para.location, length: length)
        return TextEdit(range: para, replacement: replacement, selection: selection)
    }

    // MARK: Bloc de code et séparateur

    private static func codeBlock(_ ns: NSString, _ sel: NSRange) -> TextEdit {
        // Curseur ou sélection dans un bloc déjà clôturé : on retire les deux lignes de clôture.
        var fences: [(line: NSRange, enclosing: NSRange)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { text, range, enclosing, _ in
            if text?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true { fences.append((range, enclosing)) }
        }
        var i = 0
        while i + 1 < fences.count {
            let open = fences[i], close = fences[i + 1]
            if open.enclosing.location <= sel.location, sel.location <= close.enclosing.upperBound {
                let whole = NSRange(location: open.enclosing.location, length: close.enclosing.upperBound - open.enclosing.location)
                let innerStart = open.enclosing.upperBound, innerEnd = close.enclosing.location
                var inner = innerEnd > innerStart ? ns.substring(with: NSRange(location: innerStart, length: innerEnd - innerStart)) : ""
                if inner.hasSuffix("\n") { inner.removeLast() }
                let closeHadNewline = close.enclosing.length > close.line.length
                return TextEdit(range: whole, replacement: inner + (closeHadNewline ? "\n" : ""),
                                selection: NSRange(location: whole.location, length: (inner as NSString).length))
            }
            i += 2
        }
        let para = ns.paragraphRange(for: sel)
        var block = ns.substring(with: para)
        let trailing = block.hasSuffix("\n")
        if trailing { block.removeLast() }
        let rep = "```\n" + block + "\n```" + (trailing ? "\n" : "")
        let caret = para.location + 4 + (block as NSString).length
        // Ligne vide : le curseur entre dans le bloc ; sinon le contenu est sélectionné.
        if block.trimmingCharacters(in: .whitespaces).isEmpty {
            return TextEdit(range: para, replacement: rep, selection: NSRange(location: para.location + 4, length: 0))
        }
        return TextEdit(range: para, replacement: rep, selection: NSRange(location: para.location + 4, length: caret - para.location - 4))
    }

    private static func separator(_ ns: NSString, _ sel: NSRange, _ ctx: Context) -> TextEdit {
        let para = ns.paragraphRange(for: sel)
        let line = ns.substring(with: para).trimmingCharacters(in: .whitespacesAndNewlines)
        let sepLength = (ctx.separator as NSString).length
        if line.isEmpty {
            let rep = ctx.separator + "\n"
            return TextEdit(range: para, replacement: rep, selection: NSRange(location: para.location + sepLength + 1, length: 0))
        }
        let hasNewline = ns.substring(with: para).hasSuffix("\n")
        let rep = (hasNewline ? "" : "\n") + ctx.separator + "\n"
        let at = para.upperBound
        return TextEdit(range: NSRange(location: at, length: 0), replacement: rep,
                        selection: NSRange(location: at + (rep as NSString).length, length: 0))
    }
}

// MARK: Styles actifs sous le curseur

extension MarkdownAssistant {
    private static let inlinePatterns: [(MarkdownAction, NSRegularExpression)] = [
        (.bold, try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")),
        (.italic, try! NSRegularExpression(pattern: "(?<![\\*\\w])(\\*|_)(?![\\s\\*_])(.+?)(?<![\\s\\*_])\\1(?![\\*\\w])")),
        (.strike, try! NSRegularExpression(pattern: "~~(?=\\S)(.+?)(?<=\\S)~~")),
        (.code, try! NSRegularExpression(pattern: "`([^`\\n]+)`")),
        (.link, try! NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")),
    ]

    /// Mises en forme qui s'appliquent là où est le curseur : les boutons correspondants de la barre s'allument.
    public static func activeActions(in text: String, selection: NSRange) -> Set<MarkdownAction> {
        let ns = text as NSString
        let loc = min(selection.location, ns.length)
        var active: Set<MarkdownAction> = []
        let para = ns.paragraphRange(for: NSRange(location: loc, length: 0))
        var line = ns.substring(with: para)
        if line.hasSuffix("\n") { line.removeLast() }

        switch headingLevel(line) {
        case 1: active.insert(.h1)
        case 2: active.insert(.h2)
        case 3: active.insert(.h3)
        default: break
        }
        if let item = ListTools.parse(line) {
            switch item.kind {
            case .bullet: active.insert(.bullet)
            case .number: active.insert(.numbered)
            case .check: active.insert(.task)
            }
        }
        if line.hasPrefix("> ") || line == ">" { active.insert(.quote) }

        // Dans un bloc de code : nombre impair de clôtures avant la ligne.
        var fences = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: para.location), options: .byParagraphs) { s, _, _, _ in
            if s?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true { fences += 1 }
        }
        if fences % 2 == 1 || line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { active.insert(.codeBlock) }

        let lineRange = NSRange(location: para.location, length: (line as NSString).length)
        for (action, regex) in inlinePatterns {
            for m in regex.matches(in: text, range: lineRange) where NSLocationInRange(loc, NSRange(location: m.range.location, length: m.range.length + 1)) {
                active.insert(action)
            }
        }
        return active
    }
}

// MARK: Couleur du texte

extension MarkdownAssistant {
    /// Couleurs proposées pour le texte (hexadécimal sans « # »), dans l'ordre des pastilles : jaune, orange, rouge, violet, bleu, cyan, vert.
    public static let palette = ["FFC71A", "FF851A", "F5423D", "9E4DDB", "337AF5", "1AB3CC", "33BD4D"]

    private static let colorSpan = try! NSRegularExpression(pattern: "<span style=\"color:#([0-9A-Fa-f]{6})\">(.*?)</span>")

    /// Couleur du texte sélectionné, en HTML en ligne (`<span style="color:#RRGGBB">…</span>`), seule façon de colorer du Markdown.
    /// `hex` nil retire la couleur. Une sélection déjà colorée change de couleur au lieu d'empiler les balises ;
    /// une sélection sur plusieurs lignes est colorée ligne par ligne (le rendu travaille ligne par ligne).
    public static func color(_ hex: String?, in text: String, selection: NSRange, context: Context = Context()) -> TextEdit {
        let ns = text as NSString
        let loc = min(selection.location, ns.length)
        let sel = NSRange(location: loc, length: min(selection.length, ns.length - loc))
        func open(_ h: String) -> String { "<span style=\"color:#\(h.uppercased())\">" }

        for m in colorSpan.matches(in: text, range: ns.paragraphRange(for: sel)) {
            let r = m.range
            guard sel.location >= r.location, sel.upperBound <= r.upperBound else { continue }
            let inner = ns.substring(with: m.range(at: 2))
            let head = hex.map { open($0) } ?? ""
            return TextEdit(range: r, replacement: hex == nil ? inner : head + inner + "</span>",
                            selection: NSRange(location: r.location + (head as NSString).length, length: (inner as NSString).length))
        }
        guard let hex else { return TextEdit(range: sel, replacement: ns.substring(with: sel), selection: sel) }
        let head = open(hex)
        if sel.length == 0 {
            let p = context.textPlaceholder
            return TextEdit(range: sel, replacement: head + p + "</span>",
                            selection: NSRange(location: sel.location + (head as NSString).length, length: (p as NSString).length))
        }
        let wrapped = ns.substring(with: sel).components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return line }
            let lead = line.prefix(while: { $0 == " " || $0 == "\t" })
            let body = line.dropFirst(lead.count)
            let tail = String(body.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
            return lead + head + body.dropLast(tail.count) + "</span>" + tail
        }.joined(separator: "\n")
        let single = !ns.substring(with: sel).contains("\n")
        return TextEdit(range: sel, replacement: wrapped,
                        selection: single ? NSRange(location: sel.location + (head as NSString).length, length: sel.length)
                                          : NSRange(location: sel.location, length: (wrapped as NSString).length))
    }
}
