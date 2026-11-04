import AppKit
import qNOTESCore

/// `qNOTES --selftest` : vérifie sans fenêtre le comportement de la zone de texte (assistant Markdown, puces, séparateur).
@MainActor
enum SelfTest {
    static func run() -> Never {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ got: String = "") {
            print(ok ? "OK    \(name)" : "ÉCHEC \(name) → \(got.debugDescription)")
            if !ok { failures += 1 }
        }
        let none = NSRange(location: NSNotFound, length: 0)
        let view = NoteTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = false
        EditorController.shared.textView = view
        Prefs.defaults.removeObject(forKey: Prefs.bulletGlyph)
        Prefs.defaults.removeObject(forKey: Prefs.separator)
        Prefs.defaults.removeObject(forKey: Prefs.smartBullets)

        view.string = "un mot"
        view.setSelectedRange(NSRange(location: 3, length: 3))
        EditorController.shared.apply(.bold)
        check("gras sur la sélection", view.string == "un **mot**", view.string)
        check("sélection conservée", (view.string as NSString).substring(with: view.selectedRange()) == "mot")
        EditorController.shared.apply(.bold)
        check("gras retiré au second appel", view.string == "un mot", view.string)

        view.string = "titre"
        view.setSelectedRange(NSRange(location: 2, length: 0))
        EditorController.shared.apply(.h2)
        check("titre moyen", view.string == "## titre", view.string)

        view.string = "- a"
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.insertNewline(nil)
        check("Retour continue la puce", view.string == "- a\n- ", view.string)
        view.insertNewline(nil)
        check("puce vide : fin de liste", view.string == "- a\n", view.string)

        view.string = "1. a"
        view.setSelectedRange(NSRange(location: 4, length: 0))
        view.insertNewline(nil)
        check("liste numérotée", view.string == "1. a\n2. ", view.string)

        view.string = "---"
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.insertNewline(nil)
        check("--- + Retour = séparateur", view.string == Separators.presets[0] + "\n", view.string)

        Prefs.defaults.set("•", forKey: Prefs.bulletGlyph)
        view.string = ""
        view.insertText("-", replacementRange: none)
        view.insertText(" ", replacementRange: none)
        check("« - » + espace = puce choisie", view.string == "• ", view.string)
        view.insertText("x", replacementRange: none)
        view.insertNewline(nil)
        check("la puce choisie continue", view.string == "• x\n• ", view.string)
        Prefs.defaults.removeObject(forKey: Prefs.bulletGlyph)

        view.string = ""
        view.insertText("[", replacementRange: none)
        view.insertText("]", replacementRange: none)
        view.insertText(" ", replacementRange: none)
        check("« [] » + espace = tâche", view.string == "- [ ] ", view.string)

        view.string = "- a"
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.insertTab(nil)
        check("Tab décale la puce", view.string == "  - a", view.string)
        view.insertBacktab(nil)
        check("Maj-Tab la ramène", view.string == "- a", view.string)

        Prefs.defaults.set(false, forKey: Prefs.smartBullets)
        view.string = "- a"
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.insertNewline(nil)
        check("puces intelligentes désactivables", view.string == "- a\n", view.string)
        Prefs.defaults.removeObject(forKey: Prefs.smartBullets)

        print(failures == 0 ? "Tout est bon." : "\(failures) échec(s).")
        exit(failures == 0 ? 0 : 1)
    }
}
