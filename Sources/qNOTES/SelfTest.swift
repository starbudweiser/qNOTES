import AppKit
import SwiftUI
import qNOTESCore

/// `qNOTES --selftest` : vérifie sans fenêtre le comportement de la zone de texte enrichie (mise en forme, puces, séparateur,
/// enregistrement RTF, conversion des anciennes notes Markdown, police).
@MainActor
enum SelfTest {
    static func run() -> Never {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ got: String = "") {
            print(ok ? "OK    \(name)" : "ÉCHEC \(name) → \(got.debugDescription)")
            if !ok { failures += 1 }
        }
        let manager = NSFontManager.shared
        let none = NSRange(location: NSNotFound, length: 0)
        let view = NoteTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = true
        EditorController.shared.textView = view
        for key in [Prefs.bulletGlyph, Prefs.separator, Prefs.smartBullets, Prefs.fontSize, Prefs.fontFamily] { Prefs.defaults.removeObject(forKey: key) }

        func reset(_ text: String) {
            view.textStorage?.setAttributedString(RichText.display(NSAttributedString(string: text), family: "", size: 16))
            view.typingAttributes = RichText.defaults(family: "", size: 16)
        }
        func font(at index: Int) -> NSFont? { view.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont }
        func bold(at index: Int) -> Bool { font(at: index).map { manager.traits(of: $0).contains(.boldFontMask) } ?? false }

        // Caractères
        reset("un mot")
        view.setSelectedRange(NSRange(location: 3, length: 3))
        EditorController.shared.apply(.bold)
        check("gras sur la sélection", bold(at: 3) && bold(at: 5) && !bold(at: 0) && view.string == "un mot", view.string)
        check("bouton gras allumé", EditorController.shared.active.contains(.bold))
        EditorController.shared.apply(.bold)
        check("gras retiré au second appel", !bold(at: 3))
        EditorController.shared.apply(.underline)
        check("souligné", (view.textStorage?.attribute(.underlineStyle, at: 4, effectiveRange: nil) as? Int ?? 0) != 0)
        EditorController.shared.apply(.strike)
        check("barré", (view.textStorage?.attribute(.strikethroughStyle, at: 4, effectiveRange: nil) as? Int ?? 0) != 0)
        EditorController.shared.applyColor("F5423D")
        let red = view.textStorage?.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
        check("couleur du texte", red != nil && abs((red?.usingColorSpace(.sRGB)?.redComponent ?? 0) - 0xF5 / 255.0) < 0.01)
        EditorController.shared.applyColor(nil)
        check("couleur retirée", RichText.rtf(from: view.textStorage ?? NSAttributedString(), appliedSize: 16).count > 0)

        // Styles de paragraphe
        reset("titre\nsuite")
        view.setSelectedRange(NSRange(location: 2, length: 0))
        EditorController.shared.apply(.title)
        check("titre : grande taille en gras", (font(at: 0)?.pointSize ?? 0) >= 16 * 1.5 && bold(at: 0), "\(font(at: 0)?.pointSize ?? 0)")
        check("la ligne suivante reste normale", (font(at: 7)?.pointSize ?? 0) == 16)
        EditorController.shared.apply(.title)
        check("titre retiré au second appel", font(at: 0)?.pointSize == 16 && !bold(at: 0))
        EditorController.shared.apply(.subtitle)
        check("sous-titre", (font(at: 0)?.pointSize ?? 0) > 16 && (font(at: 0)?.pointSize ?? 0) < 16 * 1.5)
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.insertNewline(nil)
        check("après un titre, retour au texte normal", (view.typingAttributes[.font] as? NSFont)?.pointSize == 16)

        // Listes de la barre d'outils
        reset("a\nb")
        view.setSelectedRange(NSRange(location: 0, length: 3))
        EditorController.shared.apply(.bullet)
        check("liste à puces sur plusieurs lignes", view.string == "• a\n• b", view.string)
        EditorController.shared.apply(.bullet)
        check("liste retirée au second appel", view.string == "a\nb", view.string)
        EditorController.shared.apply(.numbered)
        check("liste numérotée", view.string == "1. a\n2. b", view.string)
        EditorController.shared.apply(.task)
        check("liste de tâches", view.string == "☐ a\n☐ b", view.string)
        reset("")
        EditorController.shared.apply(.bullet)
        check("puce sur ligne vide", view.string == "• ", view.string)
        check("le curseur reste après la puce", view.selectedRange().location == 2, "\(view.selectedRange())")
        reset("x")
        view.setSelectedRange(NSRange(location: 1, length: 0))
        EditorController.shared.apply(.bullet)
        let hanging = (view.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
        check("retrait suspendu sous la puce", hanging > 0, "\(hanging)")

        // Puces intelligentes (texte)
        reset("• a")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.insertNewline(nil)
        check("Retour continue la puce", view.string == "• a\n• ", view.string)
        view.insertNewline(nil)
        check("puce vide : fin de liste", view.string == "• a\n", view.string)
        reset("1. a")
        view.setSelectedRange(NSRange(location: 4, length: 0))
        view.insertNewline(nil)
        check("liste numérotée", view.string == "1. a\n2. ", view.string)
        reset("☐ a")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.insertNewline(nil)
        check("la case continue", view.string == "☐ a\n☐ ", view.string)
        reset("---")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.insertNewline(nil)
        check("--- + Retour = séparateur", view.string == Separators.presets[0] + "\n", view.string)
        reset("")
        view.insertText("-", replacementRange: none)
        view.insertText(" ", replacementRange: none)
        check("« - » + espace = puce par défaut", view.string == "• ", view.string)
        Prefs.defaults.set("▸", forKey: Prefs.bulletGlyph)
        reset("")
        view.insertText("-", replacementRange: none)
        view.insertText(" ", replacementRange: none)
        check("« - » + espace = puce choisie", view.string == "▸ ", view.string)
        Prefs.defaults.removeObject(forKey: Prefs.bulletGlyph)
        reset("")
        view.insertText("[", replacementRange: none)
        view.insertText("]", replacementRange: none)
        view.insertText(" ", replacementRange: none)
        check("« [] » + espace = case", view.string == "☐ ", view.string)
        reset("• a")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.insertTab(nil)
        check("Tab décale la puce", view.string == "  • a", view.string)
        view.insertBacktab(nil)
        check("Maj-Tab la ramène", view.string == "• a", view.string)
        Prefs.defaults.set(false, forKey: Prefs.smartBullets)
        reset("• a")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.insertNewline(nil)
        check("puces intelligentes désactivables", view.string == "• a\n", view.string)
        Prefs.defaults.removeObject(forKey: Prefs.smartBullets)

        // Séparateur de la barre d'outils
        reset("avant\naprès")
        view.setSelectedRange(NSRange(location: 2, length: 0))
        EditorController.shared.apply(.separator)
        check("séparateur sous la ligne", view.string == "avant\n\(Separators.presets[0])\naprès", view.string)

        // Enregistrement RTF
        let styled = NSMutableAttributedString(attributedString: RichText.display(NSAttributedString(string: "Salut tout le monde"), family: "Georgia", size: 16))
        styled.addAttribute(.font, value: RichText.font(family: "Georgia", size: 16, bold: true), range: NSRange(location: 0, length: 5))
        styled.addAttribute(.foregroundColor, value: NSColor(Color(hex: "337AF5")), range: NSRange(location: 6, length: 4))
        let data = RichText.rtf(from: styled, appliedSize: 16)
        let back = RichText.attributed(rtf: data)
        check("RTF : texte intact", back.string == "Salut tout le monde", back.string)
        let backFont = back.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        check("RTF : gras et police gardés", backFont.map { manager.traits(of: $0).contains(.boldFontMask) && $0.familyName == "Georgia" } ?? false, backFont?.fontName ?? "nil")
        check("RTF : couleur gardée", (back.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB).map { abs($0.blueComponent - 0xF5 / 255.0) < 0.02 } ?? false)
        var defaultColorKept = false
        back.enumerateAttribute(.foregroundColor, in: NSRange(location: 11, length: 8)) { value, _, _ in
            if let c = value as? NSColor, let s = c.usingColorSpace(.sRGB), s.redComponent > 0.8, s.greenComponent > 0.8 { defaultColorKept = true }
        }
        check("RTF : la couleur du thème n'est pas enregistrée", !defaultColorKept)
        let big = RichText.display(back, family: "Georgia", size: 20)
        check("affichage : taille mise à l'échelle", (big.attribute(.font, at: 10, effectiveRange: nil) as? NSFont)?.pointSize == 20)
        let saved20 = RichText.attributed(rtf: RichText.rtf(from: big, appliedSize: 20))
        check("RTF : taille ramenée à la référence", (saved20.attribute(.font, at: 10, effectiveRange: nil) as? NSFont)?.pointSize == 16)
        let swapped = RichText.display(back, family: "Menlo", size: 16)
        let swappedFont = swapped.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        check("affichage : police du réglage, gras gardé", swappedFont.map { $0.familyName == "Menlo" && manager.traits(of: $0).contains(.boldFontMask) } ?? false, swappedFont?.fontName ?? "nil")

        // Ajout de texte à une note enrichie (Raccourcis)
        let appended = RTFAppend.append(text: "\nÀ {x}", to: data).map { RichText.attributed(rtf: $0).string }
        check("ajout de texte à un RTF", appended == "Salut tout le monde\nÀ {x}", appended ?? "nil")

        // Ancienne note Markdown
        let migrated = RichText.attributed(markdown: "# Titre\n**gras** et *italique*\n- [ ] tâche\n- puce")
        check("Markdown converti : balises retirées", migrated.string == "Titre\ngras et italique\n☐ tâche\n• puce", migrated.string)
        let titleFont = migrated.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        check("Markdown converti : titre en grand et en gras", (titleFont?.pointSize ?? 0) > 20 && titleFont.map { manager.traits(of: $0).contains(.boldFontMask) } == true)
        let boldWord = migrated.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
        check("Markdown converti : gras", boldWord.map { manager.traits(of: $0).contains(.boldFontMask) } == true)

        // Collage
        let foreign = NSMutableAttributedString(string: "texte rouge", attributes: [.font: NSFont(name: "Times New Roman", size: 12) ?? .systemFont(ofSize: 12), .foregroundColor: NSColor.black])
        foreign.addAttribute(.foregroundColor, value: NSColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1), range: NSRange(location: 6, length: 5))
        foreign.addAttribute(.font, value: NSFontManager.shared.convert(NSFont(name: "Times New Roman", size: 12) ?? .systemFont(ofSize: 12), toHaveTrait: .boldFontMask), range: NSRange(location: 0, length: 5))
        let pasted = RichText.normalizedPaste(foreign, family: "Georgia", size: 16)
        let pastedFont = pasted.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        check("collage : police du réglage, gras gardé", pastedFont.map { $0.familyName == "Georgia" && $0.pointSize == 16 && manager.traits(of: $0).contains(.boldFontMask) } ?? false, pastedFont?.fontName ?? "nil")
        check("collage : noir neutralisé", pasted.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor === RichText.defaultColor)
        check("collage : couleur franche gardée", (pasted.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB).map { $0.redComponent > 0.8 } ?? false)

        print(failures == 0 ? "Tout est bon." : "\(failures) échec(s).")
        exit(failures == 0 ? 0 : 1)
    }
}
