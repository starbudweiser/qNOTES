import Foundation
import Testing
@testable import qNOTESCore

@Suite struct ListToolsTests {
    @Test func returnContinuesBullets() {
        #expect(ListTools.onReturn(line: "- une idée") == .insert("\n- "))
        #expect(ListTools.onReturn(line: "  • sous-point") == .insert("\n  • "))
        #expect(ListTools.onReturn(line: "3. trois") == .insert("\n4. "))
        #expect(ListTools.onReturn(line: "- [x] fait") == .insert("\n- [ ] "))
        #expect(ListTools.onReturn(line: "texte simple") == .none)
    }

    @Test func emptyBulletEndsList() {
        #expect(ListTools.onReturn(line: "- ") == .endList(2))
        #expect(ListTools.onReturn(line: "  ▸ ") == .endList(4))
        #expect(ListTools.onReturn(line: "- [ ] ") == .endList(6))
        #expect(ListTools.onReturn(line: "2. ") == .endList(3))
    }

    @Test func glyphSubstitution() {
        #expect(ListTools.bulletSubstitution(beforeCursor: "-", glyph: "•") == "• ")
        #expect(ListTools.bulletSubstitution(beforeCursor: "  *", glyph: "▸") == "  ▸ ")
        #expect(ListTools.bulletSubstitution(beforeCursor: "-", glyph: "-") == nil)
        #expect(ListTools.bulletSubstitution(beforeCursor: "[]", glyph: "•") == "• [ ] ")
        #expect(ListTools.bulletSubstitution(beforeCursor: "a -", glyph: "•") == nil)
    }

    @Test func checkboxToggle() {
        #expect(ListTools.toggled("- [ ] acheter") == "- [x] acheter")
        #expect(ListTools.toggled("• [x] acheter") == "• [ ] acheter")
        #expect(ListTools.toggled("- acheter") == nil)
        #expect(ListTools.parse("- [ ] a")?.checkboxRange == 2..<5)
    }

    @Test func indentation() {
        #expect(ListTools.indented("- a") == "  - a")
        #expect(ListTools.outdented("  - a") == "- a")
        #expect(ListTools.outdented("- a") == "- a")
    }

    @Test func separators() {
        #expect(Separators.isTrigger("---"))
        #expect(Separators.isTrigger("*****"))
        #expect(!Separators.isTrigger("--"))
        #expect(!Separators.isTrigger("-*-"))
        #expect(Separators.isSeparatorLine("• • •", custom: "⁂"))
        #expect(Separators.isSeparatorLine("⁂", custom: "⁂"))
        #expect(!Separators.isSeparatorLine("texte", custom: "⁂"))
    }
}

@Suite struct NoteTests {
    @Test func titleSkipsMarkdownMarkers() {
        #expect(Note(text: "# Courses\n- lait").title == "Courses")
        #expect(Note(text: "\n\n- [ ] appeler Paul").title == "appeler Paul")
        #expect(Note(text: "").title == "")
        #expect(Note(text: "Titre\nsuite du texte").preview == "suite du texte")
        #expect(Note(text: "# Courses\n- [x] Pain\n- [ ] Lait\n────\n```\ncode\n```").preview == "Pain · Lait · code")
    }

    @Test func counts() {
        let c = TextCounts("Bonjour le monde\ndeux lignes")
        #expect(c.words == 5 && c.lines == 2 && c.characters == 28)
        #expect(TextCounts("").words == 0)
    }
}

@MainActor @Suite struct StoreTests {
    func temp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("qnotes-" + UUID().uuidString) }

    @Test func createUpdatePersistReload() {
        let dir = temp()
        let store = NoteStore(directory: dir)
        let note = store.create(text: "a")
        store.update(id: note.id, text: "bonjour")
        store.flush()
        let again = NoteStore(directory: dir)
        #expect(again.notes.count == 1 && again.notes[0].text == "bonjour")
    }

    @Test func externalChangesAreSeen() throws {
        let dir = temp()
        let a = NoteStore(directory: dir)
        let b = NoteStore(directory: dir)
        let note = a.create(text: "v1")
        a.flush()
        b.reload()
        #expect(b.notes.first?.text == "v1")
        Thread.sleep(forTimeInterval: 1.1)
        b.update(id: note.id, text: "v2")
        b.flush()
        a.reload()
        #expect(a.notes.first?.text == "v2")
        b.delete(id: note.id)
        a.reload()
        #expect(a.notes.isEmpty)
    }

    /// Régression : un dossier derrière un lien symbolique ne doit jamais faire supprimer les notes.
    @Test func symlinkedDirectoryKeepsFiles() throws {
        let real = temp()
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = temp()
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let seed = NoteStore(directory: real)
        let note = seed.create(text: "précieuse")
        seed.flush()
        let viaLink = NoteStore(directory: link)
        viaLink.reload()
        #expect(viaLink.notes.count == 1)
        #expect(FileManager.default.fileExists(atPath: real.appendingPathComponent("\(note.id.uuidString).json").path))
        #expect(NoteStore(directory: real).notes.first?.text == "précieuse")
    }

    @Test func conflictCopyKeepsNewest() throws {
        let dir = temp()
        let store = NoteStore(directory: dir)
        let note = store.create(text: "ancienne")
        store.flush()
        Thread.sleep(forTimeInterval: 1.1)
        var newer = note
        newer.text = "récente"; newer.modified = Date()
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try enc.encode(newer).write(to: dir.appendingPathComponent("\(note.id.uuidString) 2.json"))
        store.reload()
        #expect(store.notes.first?.text == "récente")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(note.id.uuidString) 2.json").path))
    }

    @Test func pinnedFirst() {
        let store = NoteStore(directory: temp())
        let first = store.create(text: "ancienne")
        _ = store.create(text: "récente")
        store.setPinned(id: first.id, true)
        #expect(store.notes.first?.id == first.id)
    }

    @Test func switchDirectoryMerges() {
        let local = temp(), cloud = temp()
        let store = NoteStore(directory: local)
        let mine = store.create(text: "locale")
        store.flush()
        let other = NoteStore(directory: cloud)
        other.create(text: "distante")
        other.flush()
        store.switchDirectory(to: cloud)
        #expect(store.notes.count == 2)
        let check = NoteStore(directory: cloud)
        #expect(check.notes.contains { $0.id == mine.id })
    }

    @Test func appendAddsLine() {
        let store = NoteStore(directory: temp())
        let n = store.create(text: "début")
        store.append(id: n.id, text: "suite")
        #expect(store.note(n.id)?.text == "début\nsuite")
    }
}

@MainActor @Suite struct BackupTests {
    @Test func createListPruneLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("qnotes-bk-" + UUID().uuidString)
        let notes = [Note(text: "a"), Note(text: "b")]
        for i in 0..<4 { try Backups.create(notes: notes, in: dir, date: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 100)) }
        #expect(Backups.list(in: dir).count == 4)
        Backups.prune(in: dir, keep: 2)
        let left = Backups.list(in: dir)
        #expect(left.count == 2 && left[0].noteCount == 2)
        #expect(Backups.load(left[0].url)?.count == 2)
        #expect(try Backups.create(notes: [], in: dir) == nil)
    }
}
