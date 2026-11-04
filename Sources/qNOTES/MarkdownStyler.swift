import AppKit
import SwiftUI
import qNOTESCore

/// Mise en forme en direct du Markdown : le texte reste du Markdown brut, mais titres, gras, italique, code, listes,
/// tâches, citations, liens et séparateurs s'affichent « comme du texte enrichi ». Les signes (#, **, `…) restent
/// visibles mais discrets, pour que l'on sache toujours ce que l'on copie.
@MainActor
enum MarkdownStyler {
    private static func ns(_ c: Color) -> NSColor { NSColor(c) }

    private static let heading = try! NSRegularExpression(pattern: "^(#{1,6})[ \\t]+")
    private static let quote = try! NSRegularExpression(pattern: "^>[ \\t]?")
    private static let bold = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italic = try! NSRegularExpression(pattern: "(?<![\\*\\w])(\\*|_)(?![\\s\\*_])(.+?)(?<![\\s\\*_])\\1(?![\\*\\w])")
    private static let strike = try! NSRegularExpression(pattern: "~~(?=\\S)(.+?)(?<=\\S)~~")
    private static let code = try! NSRegularExpression(pattern: "`([^`\\n]+)`")
    private static let link = try! NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")
    private static let colorSpan = try! NSRegularExpression(pattern: "<span style=\"color:#([0-9A-Fa-f]{6})\">(.*?)</span>")
    private static let url = try! NSRegularExpression(pattern: "https?://[^\\s<>\\)\\]]+")

    static func apply(to storage: NSTextStorage, fontSize: CGFloat, separator: String, hideMarkers: Bool = false, active: NSRange = NSRange(location: 0, length: 0)) {
        let full = NSRange(location: 0, length: storage.length)
        let base = NSFont.systemFont(ofSize: fontSize)
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize * 0.92, weight: .regular)
        let text = ns(Socle.C.text), muted = ns(Socle.C.textMuted), subtle = ns(Socle.C.textSubtle)
        let accent = ns(Socle.C.accentText), success = ns(Socle.C.success), codeBG = ns(Socle.C.bgSunken)

        let basePara = NSMutableParagraphStyle()
        basePara.lineHeightMultiple = 1.22
        basePara.paragraphSpacing = 3

        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: text, .paragraphStyle: basePara], range: full)
        let string = storage.string as NSString
        var inFence = false

        let hiddenFont = NSFont.systemFont(ofSize: 1)
        string.enumerateSubstrings(in: full, options: [.byParagraphs, .substringNotRequired]) { _, range, enclosing, _ in
            // Mise en page : les balises sont masquées, sauf sur la ligne où se trouve le curseur ou la sélection.
            let loc = active.location
            let isActive = (loc >= enclosing.location && loc < enclosing.upperBound) || (loc == storage.length && enclosing.upperBound == storage.length)
                || NSIntersectionRange(active, enclosing).length > 0
            let hideHere = hideMarkers && !isActive
            func dim(_ r: NSRange) {
                if hideHere { storage.addAttributes([.font: hiddenFont, .foregroundColor: NSColor.clear], range: r) }
                else { storage.addAttribute(.foregroundColor, value: subtle, range: r) }
            }
            let line = string.substring(with: range)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inFence.toggle()
                storage.addAttributes([.font: mono, .foregroundColor: subtle], range: range)
                return
            }
            if inFence {
                storage.addAttributes([.font: mono, .backgroundColor: codeBG], range: range)
                return
            }
            if Separators.isTrigger(line) || Separators.isSeparatorLine(line, custom: separator) {
                storage.addAttribute(.foregroundColor, value: subtle, range: range)
                return
            }

            var contentStart = range.location
            if let m = heading.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let level = m.range(at: 1).length
                let scale: [CGFloat] = [1.6, 1.38, 1.2, 1.1, 1.05, 1.0]
                let font = NSFont.systemFont(ofSize: fontSize * scale[level - 1], weight: .bold)
                storage.addAttributes([.font: font, .foregroundColor: ns(Socle.C.textStrong)], range: range)
                dim(NSRange(location: range.location, length: m.range.length))
                contentStart += m.range.length
            } else if let m = quote.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let para = basePara.mutableCopy() as! NSMutableParagraphStyle
                para.headIndent = 14; para.firstLineHeadIndent = 14
                storage.addAttributes([.foregroundColor: muted, .paragraphStyle: para], range: range)
                dim(NSRange(location: range.location, length: m.range.length))
                contentStart += m.range.length
            } else if let item = ListTools.parse(line) {
                let prefix = String(line.prefix(item.markerLength))
                let width = (prefix as NSString).size(withAttributes: [.font: base]).width
                let para = basePara.mutableCopy() as! NSMutableParagraphStyle
                para.headIndent = width
                storage.addAttribute(.paragraphStyle, value: para, range: range)
                let markerStart = range.location + item.indent.count
                let markerEnd = range.location + item.markerLength
                storage.addAttribute(.foregroundColor, value: accent, range: NSRange(location: markerStart, length: markerEnd - markerStart))
                contentStart = markerEnd
                if case .check(_, let done) = item.kind, let box = item.checkboxRange {
                    storage.addAttribute(.foregroundColor, value: done ? success : accent,
                                         range: NSRange(location: range.location + box.lowerBound, length: 3))
                    if done, contentStart < range.location + range.length {
                        storage.addAttributes([.foregroundColor: subtle, .strikethroughStyle: NSUnderlineStyle.single.rawValue],
                                              range: NSRange(location: contentStart, length: range.location + range.length - contentStart))
                    }
                }
            }

            inline(storage, in: NSRange(location: contentStart, length: range.location + range.length - contentStart),
                   mono: mono, codeBG: codeBG, accent: accent, dim: dim)
        }
        storage.endEditing()
    }

    private static func inline(_ storage: NSTextStorage, in range: NSRange, mono: NSFont, codeBG: NSColor, accent: NSColor, dim: (NSRange) -> Void) {
        guard range.length > 1 else { return }
        let string = storage.string
        func mark(_ re: NSRegularExpression, markerLength: (NSTextCheckingResult) -> Int, style: (NSRange) -> Void) {
            for m in re.matches(in: string, range: range) {
                style(m.range)
                let n = markerLength(m)
                dim(NSRange(location: m.range.location, length: n))
                dim(NSRange(location: m.range.upperBound - n, length: n))
            }
        }
        func trait(_ t: NSFontTraitMask) -> (NSRange) -> Void {
            { r in
                storage.enumerateAttribute(.font, in: r) { value, sub, _ in
                    guard let f = value as? NSFont else { return }
                    storage.addAttribute(.font, value: NSFontManager.shared.convert(f, toHaveTrait: t), range: sub)
                }
            }
        }
        mark(bold, markerLength: { $0.range(at: 1).length }, style: trait(.boldFontMask))
        mark(italic, markerLength: { $0.range(at: 1).length }, style: trait(.italicFontMask))
        mark(strike, markerLength: { _ in 2 }, style: { storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: $0) })
        mark(code, markerLength: { _ in 1 }, style: { storage.addAttributes([.font: mono, .backgroundColor: codeBG], range: $0) })

        for m in colorSpan.matches(in: string, range: range) {
            let inner = m.range(at: 2)
            storage.addAttribute(.foregroundColor, value: NSColor(Color(hex: (string as NSString).substring(with: m.range(at: 1)))), range: inner)
            dim(NSRange(location: m.range.location, length: inner.location - m.range.location))   // <span style="color:#…">
            dim(NSRange(location: inner.upperBound, length: m.range.upperBound - inner.upperBound)) // </span>
        }
        for m in link.matches(in: string, range: range) {
            let target = (string as NSString).substring(with: m.range(at: 2))
            let label = m.range(at: 1)
            dim(NSRange(location: m.range.location, length: 1))                                    // [
            dim(NSRange(location: label.upperBound, length: m.range.upperBound - label.upperBound)) // ](adresse)
            storage.addAttributes([.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue], range: label)
            if let u = URL(string: target) { storage.addAttribute(.link, value: u, range: m.range) }
        }
        for m in url.matches(in: string, range: range) {
            // Une adresse déjà prise dans un lien [texte](adresse) garde son rendu.
            if storage.attribute(.link, at: m.range.location, effectiveRange: nil) != nil { continue }
            let raw = (string as NSString).substring(with: m.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
            if let u = URL(string: raw) {
                let r = NSRange(location: m.range.location, length: (raw as NSString).length)
                storage.addAttributes([.link: u, .foregroundColor: accent], range: r)
            }
        }
    }
}
