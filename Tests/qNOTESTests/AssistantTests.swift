import Foundation
import Testing
@testable import qNOTESCore

@Suite struct AssistantTests {
    let ctx = MarkdownAssistant.Context(glyph: "-", separator: "───", textPlaceholder: "texte", urlPlaceholder: "adresse")

    /// Applique l'action et renvoie (texte obtenu, texte sélectionné ensuite).
    func run(_ action: MarkdownAction, _ text: String, _ sel: NSRange, _ c: MarkdownAssistant.Context? = nil) -> (String, String) {
        let e = MarkdownAssistant.edit(action, in: text, selection: sel, context: c ?? ctx)
        let result = (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
        return (result, (result as NSString).substring(with: e.selection))
    }

    func range(_ text: String, _ word: String) -> NSRange { (text as NSString).range(of: word) }

    @Test func boldWrapsAndUnwraps() {
        let t = "un mot ici"
        let (wrapped, sel) = run(.bold, t, range(t, "mot"))
        #expect(wrapped == "un **mot** ici" && sel == "mot")
        let (back, _) = run(.bold, wrapped, range(wrapped, "mot"))
        #expect(back == t)
        let (back2, _) = run(.bold, wrapped, range(wrapped, "**mot**"))
        #expect(back2 == t)
    }

    @Test func emptySelectionInsertsPlaceholder() {
        let (r, sel) = run(.bold, "", NSRange(location: 0, length: 0))
        #expect(r == "**texte**" && sel == "texte")
        let (c, _) = run(.code, "a ", NSRange(location: 2, length: 0))
        #expect(c == "a `texte`")
    }

    @Test func italicIsNotConfusedWithBold() {
        let t = "**gras**"
        let (r, _) = run(.italic, t, range(t, "gras"))
        #expect(r == "***gras***")
        let (r2, _) = run(.italic, "*a*", range("*a*", "a"))
        #expect(r2 == "a")
        let (r3, _) = run(.italic, "x", range("x", "x"))
        #expect(r3 == "*x*")
    }

    @Test func strikeAndCode() {
        #expect(run(.strike, "a b", range("a b", "b")).0 == "a ~~b~~")
        #expect(run(.code, "a b", range("a b", "b")).0 == "a `b`")
    }

    @Test func linkSelectsAddress() {
        let t = "voir site"
        let (r, sel) = run(.link, t, range(t, "site"))
        #expect(r == "voir [site](adresse)" && sel == "adresse")
        let (e, s2) = run(.link, "", NSRange(location: 0, length: 0))
        #expect(e == "[texte](adresse)" && s2 == "texte")
    }

    @Test func headingsToggleAndReplace() {
        #expect(run(.h1, "Titre", NSRange(location: 2, length: 0)).0 == "# Titre")
        #expect(run(.h2, "# Titre", NSRange(location: 0, length: 0)).0 == "## Titre")
        #expect(run(.h2, "## Titre", NSRange(location: 0, length: 0)).0 == "Titre")
        #expect(run(.h3, "- liste", NSRange(location: 0, length: 0)).0 == "### liste")
    }

    @Test func listsOnSeveralLines() {
        let t = "un\ndeux\n\ntrois"
        let all = NSRange(location: 0, length: (t as NSString).length)
        #expect(run(.bullet, t, all).0 == "- un\n- deux\n\n- trois")
        #expect(run(.numbered, t, all).0 == "1. un\n2. deux\n\n3. trois")
        #expect(run(.task, t, all).0 == "- [ ] un\n- [ ] deux\n\n- [ ] trois")
        let bulleted = run(.bullet, t, all).0
        #expect(run(.bullet, bulleted, NSRange(location: 0, length: (bulleted as NSString).length)).0 == t)
    }

    @Test func switchBetweenListKinds() {
        #expect(run(.numbered, "- a\n- b", NSRange(location: 0, length: 7)).0 == "1. a\n2. b")
        #expect(run(.task, "1. a", NSRange(location: 0, length: 0)).0 == "- [ ] a")
        var c = ctx; c.glyph = "•"
        #expect(run(.bullet, "a", NSRange(location: 0, length: 0), c).0 == "• a")
    }

    @Test func nestedIndentIsKept() {
        #expect(run(.bullet, "  a", NSRange(location: 0, length: 0)).0 == "  - a")
    }

    @Test func quoteToggles() {
        #expect(run(.quote, "a\nb", NSRange(location: 0, length: 3)).0 == "> a\n> b")
        #expect(run(.quote, "> a\n> b", NSRange(location: 0, length: 7)).0 == "a\nb")
    }

    @Test func emptyLineGetsMarker() {
        #expect(run(.bullet, "", NSRange(location: 0, length: 0)).0 == "- ")
        #expect(run(.h1, "x\n", NSRange(location: 2, length: 0)).0 == "x\n# ")
    }

    @Test func codeBlock() {
        let (r, _) = run(.codeBlock, "let x", NSRange(location: 0, length: 0))
        #expect(r == "```\nlet x\n```")
        #expect(run(.codeBlock, r, NSRange(location: 5, length: 0)).0 == "let x")
        let (empty, sel) = run(.codeBlock, "", NSRange(location: 0, length: 0))
        #expect(empty == "```\n\n```" && sel == "")
    }

    @Test func separatorIsInsertedAfterLine() {
        #expect(run(.separator, "titre", NSRange(location: 1, length: 0)).0 == "titre\n───\n")
        #expect(run(.separator, "a\nb", NSRange(location: 0, length: 0)).0 == "a\n───\nb")
        #expect(run(.separator, "", NSRange(location: 0, length: 0)).0 == "───\n")
    }

    @Test func accentsAndEmojiKeepRangesValid() {
        let t = "café 😀 ok"
        let (r, sel) = run(.bold, t, range(t, "😀"))
        #expect(r == "café **😀** ok" && sel == "😀")
    }

    @Test func activeActionsFollowTheCaret() {
        let t = "# Titre\nun **mot** et `code`\n- [ ] tâche\n> cite\n```\nx\n```"
        func active(_ word: String) -> Set<MarkdownAction> { MarkdownAssistant.activeActions(in: t, selection: NSRange(location: (t as NSString).range(of: word).location + 1, length: 0)) }
        #expect(active("Titre") == [.h1])
        #expect(active("mot") == [.bold])
        #expect(active("code") == [.code])
        #expect(active("tâche") == [.task])
        #expect(active("cite") == [.quote])
        #expect(active("x").contains(.codeBlock))
        #expect(MarkdownAssistant.activeActions(in: "texte simple", selection: NSRange(location: 3, length: 0)).isEmpty)
        #expect(MarkdownAssistant.activeActions(in: "1. a", selection: NSRange(location: 4, length: 0)) == [.numbered])
    }
}
