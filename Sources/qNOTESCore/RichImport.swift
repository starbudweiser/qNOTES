import Foundation

/// Un morceau de texte et sa mise en forme.
public struct RichRun: Equatable, Sendable {
    public var text: String
    public var bold = false
    public var italic = false
    public var strike = false
    public var mono = false
    /// « RRGGBB »
    public var color: String?
    public var link: String?

    public init(_ text: String) { self.text = text }

    func sameStyle(as other: RichRun) -> Bool {
        bold == other.bold && italic == other.italic && strike == other.strike && mono == other.mono && color == other.color && link == other.link
    }
}

public enum RichLineStyle: Equatable, Sendable {
    case body, title, subtitle, minor, quote, code, rule
}

/// Une ligne (un paragraphe) d'une ancienne note Markdown, prête à devenir du texte enrichi.
public struct RichLine: Equatable, Sendable {
    public var style: RichLineStyle
    /// Marqueur de liste déjà écrit (« • », « 1. », « ☐ »), indentation comprise.
    public var prefix: String
    public var runs: [RichRun]

    public var text: String { prefix + runs.map(\.text).joined() }
}

/// Conversion d'une note Markdown (anciennes notes, imports Tot, fichiers .md) en lignes de texte enrichi : les balises
/// disparaissent, la mise en forme passe en attributs. Chaque ligne du texte reste une ligne.
public enum RichImport {
    private enum Kind { case bold, italic, strike, code, link, color, url }

    private static let patterns: [(Kind, NSRegularExpression)] = [
        (.link, try! NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")),
        (.color, try! NSRegularExpression(pattern: "<span style=\"color:#([0-9A-Fa-f]{6})\">(.*?)</span>")),
        (.code, try! NSRegularExpression(pattern: "`([^`\\n]+)`")),
        (.bold, try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")),
        (.strike, try! NSRegularExpression(pattern: "~~(?=\\S)(.+?)(?<=\\S)~~")),
        (.italic, try! NSRegularExpression(pattern: "(?<![\\*\\w])(\\*|_)(?![\\s\\*_])(.+?)(?<![\\s\\*_])\\1(?![\\*\\w])")),
        (.url, try! NSRegularExpression(pattern: "https?://[^\\s<>\\)\\]]+")),
    ]
    private static let heading = try! NSRegularExpression(pattern: "^(#{1,6})[ \\t]+")
    private static let quote = try! NSRegularExpression(pattern: "^>[ \\t]?")

    public static func parse(_ markdown: String) -> [RichLine] {
        var lines: [RichLine] = []
        var inFence = false
        for raw in markdown.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            if inFence {
                var run = RichRun(raw); run.mono = true
                lines.append(RichLine(style: .code, prefix: "", runs: raw.isEmpty ? [] : [run]))
                continue
            }
            if Separators.isTrigger(raw) {
                lines.append(RichLine(style: .rule, prefix: "", runs: [RichRun(Separators.presets[0])]))
                continue
            }
            if Separators.isSeparatorLine(raw, custom: "") {
                lines.append(RichLine(style: .rule, prefix: "", runs: [RichRun(trimmed)]))
                continue
            }
            let range = NSRange(location: 0, length: (raw as NSString).length)
            if let m = heading.firstMatch(in: raw, range: range) {
                let level = m.range(at: 1).length
                let content = (raw as NSString).substring(from: m.range.length)
                lines.append(RichLine(style: level == 1 ? .title : level == 2 ? .subtitle : .minor, prefix: "", runs: inline(content)))
            } else if let m = quote.firstMatch(in: raw, range: range) {
                lines.append(RichLine(style: .quote, prefix: "", runs: inline((raw as NSString).substring(from: m.range.length))))
            } else if let item = ListTools.parse(raw) {
                let marker: String
                switch item.kind {
                case .bullet(let c): marker = "-*+".contains(c) ? "•" : String(c)
                case .number(let n, let sep): marker = "\(n)\(sep)"
                case .check(_, let done): marker = done ? "☑" : "☐"
                }
                var runs = inline(item.content)
                if case .check(_, true) = item.kind { for index in runs.indices { runs[index].strike = true } }
                lines.append(RichLine(style: .body, prefix: item.indent + marker + " ", runs: runs))
            } else {
                lines.append(RichLine(style: .body, prefix: "", runs: inline(raw)))
            }
        }
        return lines
    }

    static func inline(_ s: String, _ base: RichRun = RichRun("")) -> [RichRun] {
        var out: [RichRun] = []
        var rest = s
        while !rest.isEmpty {
            let ns = rest as NSString
            let full = NSRange(location: 0, length: ns.length)
            var best: (Kind, NSTextCheckingResult)?
            for (kind, re) in patterns {
                if let m = re.firstMatch(in: rest, range: full), best == nil || m.range.location < best!.1.range.location { best = (kind, m) }
            }
            guard let (kind, m) = best else { var r = base; r.text = rest; out.append(r); break }
            if m.range.location > 0 { var r = base; r.text = ns.substring(to: m.range.location); out.append(r) }
            var style = base
            var inner = ""
            switch kind {
            case .bold: style.bold = true; inner = ns.substring(with: m.range(at: 2))
            case .italic: style.italic = true; inner = ns.substring(with: m.range(at: 2))
            case .strike: style.strike = true; inner = ns.substring(with: m.range(at: 1))
            case .code: style.mono = true; inner = ns.substring(with: m.range(at: 1))
            case .link: style.link = ns.substring(with: m.range(at: 2)); inner = ns.substring(with: m.range(at: 1))
            case .color: style.color = ns.substring(with: m.range(at: 1)).uppercased(); inner = ns.substring(with: m.range(at: 2))
            case .url: style.link = ns.substring(with: m.range); inner = style.link ?? ""
            }
            if kind == .code || kind == .url { var r = style; r.text = inner; out.append(r) } else { out += inline(inner, style) }
            rest = ns.substring(from: m.range.upperBound)
        }
        var merged: [RichRun] = []
        for run in out where !run.text.isEmpty {
            if var last = merged.last, last.sameStyle(as: run) { last.text += run.text; merged[merged.count - 1] = last }
            else { merged.append(run) }
        }
        return merged
    }
}
