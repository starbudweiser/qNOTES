import AppKit
import SwiftUI
import qNOTESCore

/// Texte enrichi des notes. Une note est enregistrée en RTF à une taille de référence (16 pt) et sans la couleur de texte par
/// défaut ni la police du réglage : à l'affichage, `display` y applique la police, la taille et la couleur du thème choisis,
/// et `rtf(from:)` fait le chemin inverse.
@MainActor
enum RichText {
    static let reference: CGFloat = 16
    nonisolated static let palette = ["FFC71A", "FF851A", "F5423D", "9E4DDB", "337AF5", "1AB3CC", "33BD4D"]
    static let titleScale: CGFloat = 1.6
    static let subtitleScale: CGFloat = 1.3

    static let defaultColor = NSColor(Socle.C.text)
    /// Valeur spéciale de la famille : police à chasse fixe du système.
    nonisolated static let monoFamily = "!mono"

    // MARK: Polices et styles de base

    static func font(family: String, size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        let manager = NSFontManager.shared
        var result: NSFont
        if family == monoFamily {
            result = .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
            if italic { result = manager.convert(result, toHaveTrait: .italicFontMask) }
            return result
        }
        if family.isEmpty || manager.font(withFamily: family, traits: [], weight: 5, size: size) == nil {
            result = .systemFont(ofSize: size, weight: bold ? .bold : .regular)
            if italic { result = manager.convert(result, toHaveTrait: .italicFontMask) }
        } else {
            var traits: NSFontTraitMask = []
            if bold { traits.insert(.boldFontMask) }
            if italic { traits.insert(.italicFontMask) }
            result = manager.font(withFamily: family, traits: traits, weight: bold ? 9 : 5, size: size) ?? .systemFont(ofSize: size)
        }
        return result
    }

    static func paragraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.22
        style.paragraphSpacing = 3
        return style
    }

    static func defaults(family: String, size: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: font(family: family, size: size), .foregroundColor: defaultColor, .paragraphStyle: paragraphStyle()]
    }

    // MARK: Lecture

    static func attributed(rtf: Data) -> NSAttributedString {
        (try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil))
            ?? NSAttributedString(string: String(data: rtf, encoding: .utf8) ?? "")
    }

    /// Ancienne note Markdown → texte enrichi à la taille de référence, balises retirées.
    static func attributed(markdown: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lines = RichImport.parse(markdown)
        for (index, line) in lines.enumerated() {
            let start = out.length
            let scale: CGFloat
            var heading = false
            switch line.style {
            case .title: scale = titleScale; heading = true
            case .subtitle: scale = subtitleScale; heading = true
            case .minor: scale = 1.12; heading = true
            default: scale = 1
            }
            let size = reference * scale
            let paragraph = paragraphStyle()
            if line.style == .quote { paragraph.firstLineHeadIndent = 16; paragraph.headIndent = 16 }
            if line.style == .rule { paragraph.alignment = .center }
            func add(_ text: String, _ run: RichRun?) {
                guard !text.isEmpty else { return }
                let bold = heading || run?.bold == true
                let italic = line.style == .quote || run?.italic == true
                var attrs: [NSAttributedString.Key: Any] = [.font: font(family: "", size: size, bold: bold, italic: italic), .paragraphStyle: paragraph]
                if run?.strike == true { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if let hex = run?.color { attrs[.foregroundColor] = NSColor(Color(hex: hex)) }
                if let link = run?.link, let url = URL(string: link) { attrs[.link] = url }
                out.append(NSAttributedString(string: text, attributes: attrs))
            }
            add(line.prefix, nil)
            for run in line.runs { add(run.text, run) }
            if index < lines.count - 1 {
                out.append(NSAttributedString(string: "\n", attributes: [.font: font(family: "", size: size, bold: heading), .paragraphStyle: paragraph]))
            } else if out.length == start {
                out.append(NSAttributedString(string: ""))
            }
        }
        return out
    }

    // MARK: Affichage

    /// Texte prêt pour la zone de texte : police, taille et couleur du réglage.
    static func display(_ source: NSAttributedString, family: String, size: CGFloat) -> NSMutableAttributedString {
        let out = NSMutableAttributedString(attributedString: source)
        restyle(out, family: family, scale: size / reference)
        return out
    }

    /// Applique la police et un changement d'échelle aux polices déjà présentes ; complète couleur et paragraphe manquants.
    static func restyle(_ s: NSMutableAttributedString, family: String, scale: CGFloat) {
        let full = NSRange(location: 0, length: s.length)
        guard full.length > 0 else { return }
        let manager = NSFontManager.shared
        s.beginEditing()
        s.enumerateAttribute(.font, in: full) { value, range, _ in
            let old = (value as? NSFont) ?? .systemFont(ofSize: reference)
            let traits = manager.traits(of: old)
            let new = font(family: family, size: old.pointSize * scale, bold: traits.contains(.boldFontMask), italic: traits.contains(.italicFontMask))
            s.addAttribute(.font, value: new, range: range)
        }
        s.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if value == nil { s.addAttribute(.foregroundColor, value: defaultColor, range: range) }
        }
        s.enumerateAttribute(.paragraphStyle, in: full) { value, range, _ in
            if value == nil { s.addAttribute(.paragraphStyle, value: paragraphStyle(), range: range) }
        }
        s.endEditing()
        fixLists(s)
    }

    /// Retrait « suspendu » des lignes de liste : le texte se range sous le texte, pas sous la puce.
    static func fixLists(_ s: NSMutableAttributedString, in range: NSRange? = nil) {
        let ns = s.string as NSString
        guard ns.length > 0 else { return }
        let target = ns.paragraphRange(for: range ?? NSRange(location: 0, length: ns.length))
        s.beginEditing()
        ns.enumerateSubstrings(in: target, options: [.byParagraphs, .substringNotRequired]) { _, paragraph, enclosing, _ in
            guard paragraph.length > 0 || enclosing.length > 0 else { return }
            let probe = min(enclosing.location, ns.length - 1)
            guard let style = (s.attribute(.paragraphStyle, at: probe, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle else { return }
            let line = ns.substring(with: paragraph)
            if let item = ListTools.parse(line) {
                let font = (s.attribute(.font, at: probe, effectiveRange: nil) as? NSFont) ?? .systemFont(ofSize: reference)
                let indent = (item.indent as NSString).size(withAttributes: [.font: font]).width
                let marker = (String(line.prefix(item.markerLength)) as NSString).size(withAttributes: [.font: font]).width
                guard style.firstLineHeadIndent != indent || style.headIndent != marker else { return }
                style.firstLineHeadIndent = indent
                style.headIndent = marker
                s.addAttribute(.paragraphStyle, value: style, range: enclosing)
            } else if style.headIndent > style.firstLineHeadIndent {
                style.headIndent = 0
                style.firstLineHeadIndent = 0
                s.addAttribute(.paragraphStyle, value: style, range: enclosing)
            }
        }
        s.endEditing()
    }

    // MARK: Enregistrement

    /// RTF à la taille de référence, sans la couleur par défaut : prêt à être enregistré dans la note.
    static func rtf(from storage: NSAttributedString, appliedSize: CGFloat) -> Data {
        let copy = NSMutableAttributedString(attributedString: storage)
        let full = NSRange(location: 0, length: copy.length)
        let factor = reference / appliedSize
        if factor != 1 {
            copy.enumerateAttribute(.font, in: full) { value, range, _ in
                guard let font = value as? NSFont else { return }
                copy.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: font.pointSize * factor) ?? font, range: range)
            }
        }
        copy.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            if let color = value as? NSColor, isDefault(color) { copy.removeAttribute(.foregroundColor, range: range) }
        }
        copy.removeAttribute(.backgroundColor, range: full)
        return (try? copy.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])) ?? Data()
    }

    /// RTF d'une note pour l'exporter ou la copier, qu'elle soit déjà enrichie ou encore en Markdown.
    static func rtf(of note: Note) -> Data {
        if let rtf = note.rtf { return rtf }
        let attributed = attributed(markdown: note.text)
        return rtf(from: display(attributed, family: "", size: reference), appliedSize: reference)
    }

    private static func isDefault(_ color: NSColor) -> Bool {
        if color == defaultColor { return true }
        var same = false
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            guard let a = color.usingColorSpace(.sRGB), let b = defaultColor.usingColorSpace(.sRGB) else { return }
            same = abs(a.redComponent - b.redComponent) < 0.01 && abs(a.greenComponent - b.greenComponent) < 0.01
                && abs(a.blueComponent - b.blueComponent) < 0.01 && a.alphaComponent > 0.99
        }
        return same
    }

    // MARK: Collage

    /// Texte enrichi collé depuis une autre appli : police, taille et couleurs neutres du réglage ; gras, italique, souligné,
    /// barré, liens et couleurs franches sont gardés.
    static func normalizedPaste(_ source: NSAttributedString, family: String, size: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString(string: source.string)
        let manager = NSFontManager.shared
        let full = NSRange(location: 0, length: source.length)
        out.addAttributes(defaults(family: family, size: size), range: full)
        source.enumerateAttributes(in: full) { attrs, range, _ in
            if let old = attrs[.font] as? NSFont {
                let traits = manager.traits(of: old)
                out.addAttribute(.font, value: font(family: family, size: size, bold: traits.contains(.boldFontMask), italic: traits.contains(.italicFontMask)), range: range)
            }
            for key in [NSAttributedString.Key.underlineStyle, .strikethroughStyle, .link] {
                if let value = attrs[key] { out.addAttribute(key, value: value, range: range) }
            }
            if let color = (attrs[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB) {
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                if s > 0.25, b > 0.2 { out.addAttribute(.foregroundColor, value: color, range: range) }
            }
        }
        return out
    }
}

extension Color {
    /// « RRGGBB » (avec ou sans #).
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
