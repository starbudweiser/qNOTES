import Foundation
import Testing
@testable import qNOTESCore

@Suite struct RichTests {
    @Test func headingsListsAndRules() {
        let lines = RichImport.parse("# Titre\n## Sous\ntexte\n- a\n1. b\n- [ ] c\n- [x] d\n---\n> cité")
        #expect(lines.map(\.style) == [.title, .subtitle, .body, .body, .body, .body, .body, .rule, .quote])
        #expect(lines.map(\.text) == ["Titre", "Sous", "texte", "• a", "1. b", "☐ c", "☑ d", Separators.presets[0], "cité"])
    }

    @Test func inlineMarksBecomeAttributes() {
        let runs = RichImport.parse("un **gras** et *italique*, ~~barré~~ `code` [lien](https://x.fr)")[0].runs
        #expect(runs.map(\.text).joined() == "un gras et italique, barré code lien")
        #expect(runs.first { $0.text == "gras" }?.bold == true)
        #expect(runs.first { $0.text == "italique" }?.italic == true)
        #expect(runs.first { $0.text == "barré" }?.strike == true)
        #expect(runs.first { $0.text == "code" }?.mono == true)
        #expect(runs.first { $0.text == "lien" }?.link == "https://x.fr")
    }

    @Test func colorSpansAndNesting() {
        let runs = RichImport.parse("<span style=\"color:#f5423d\">**rouge**</span> fin")[0].runs
        #expect(runs.first?.text == "rouge")
        #expect(runs.first?.bold == true)
        #expect(runs.first?.color == "F5423D")
        #expect(runs.last?.color == nil)
    }

    @Test func everyLineStaysALine() {
        let lines = RichImport.parse("a\nb\n\nc")
        #expect(lines.count == 4)
        #expect(lines[2].text == "")
    }

    @Test func codeFencesBecomeMonospaceLines() {
        let lines = RichImport.parse("```\nlet x = 1\n```")
        #expect(lines.count == 1)
        #expect(lines[0].style == .code)
        #expect(lines[0].runs.first?.mono == true)
    }

    @Test func bareUrlsBecomeLinks() {
        let runs = RichImport.parse("voir https://exemple.fr/a.")[0].runs
        #expect(runs.contains { $0.link == "https://exemple.fr/a." || $0.link == "https://exemple.fr/a" })
    }

    @Test func toggleListStyles() {
        #expect(ListTools.toggle(.bullet, lines: ["a", "b"], glyph: "•") == ["• a", "• b"])
        #expect(ListTools.toggle(.bullet, lines: ["• a", "• b"], glyph: "•") == ["a", "b"])
        #expect(ListTools.toggle(.numbered, lines: ["a", "", "b"], glyph: "•") == ["1. a", "", "2. b"])
        #expect(ListTools.toggle(.task, lines: ["• a"], glyph: "•") == ["☐ a"])
        #expect(ListTools.toggle(.bullet, lines: [""], glyph: "•") == ["• "])
        #expect(ListTools.toggle(.bullet, lines: ["  a"], glyph: "•") == ["  • a"])
    }

    @Test func glyphCheckboxes() {
        #expect(ListTools.toggled("☐ acheter") == "☑ acheter")
        #expect(ListTools.toggled("☑ acheter") == "☐ acheter")
        #expect(ListTools.parse("☐ a")?.checkboxRange == 0..<1)
        #expect(ListTools.onReturn(line: "☑ fait") == .insert("\n☐ "))
        #expect(ListTools.onReturn(line: "☐ ") == .endList(2))
    }

    @Test func richNoteTitleKeepsMarkers() {
        let rich = Note(text: "• Liste\n**gras** reste", rtf: Data())
        #expect(rich.title == "Liste")
        #expect(rich.preview == "**gras** reste")
        #expect(Note(text: "**gras** reste").title == "gras reste")
    }

    @Test func oldNotesDecodeWithoutRtf() throws {
        let json = #"{"id":"6E1B5E7C-7A0B-4E8E-9C1D-0A1B2C3D4E5F","text":"a","created":"2026-01-01T00:00:00Z","modified":"2026-01-01T00:00:00Z","pinned":false}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let note = try decoder.decode(Note.self, from: Data(json.utf8))
        #expect(note.rtf == nil)
    }

    @Test func rtfAppendEscapes() {
        let rtf = Data("{\\rtf1\\ansi\\deff0 {\\fonttbl{\\f0 Helvetica;}}\\f0 Salut}".utf8)
        let out = String(data: RTFAppend.append(text: "\né{x}", to: rtf)!, encoding: .utf8)!
        #expect(out.hasSuffix("\\par\\pard\\plain \\u233?\\{x\\}\n}"))
    }
}
