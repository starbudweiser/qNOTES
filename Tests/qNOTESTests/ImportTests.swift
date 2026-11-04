import Foundation
import Testing
@testable import qNOTESCore

@MainActor @Suite struct ImportTests {
    let sample = #"""
    {"tot_backup":"1.0","dots":[
      {"text":"**Courses**\n- lait","selectionRich":"0,0","selectionPlain":"0,0","view":"rich","date":"2026-11-04T09:29:49.938Z"},
      {"text":"  \n","view":"rich","date":"2026-11-01T22:59:26.370Z"},
      {"text":"Autre note","view":"plain","date":"2026-10-31T18:00:15Z"}
    ]}
    """#

    func temp() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("qnotes-imp-" + UUID().uuidString) }

    @Test func parsesTotBackupAndSkipsEmptyDots() throws {
        let notes = try #require(Importer.parseTot(Data(sample.utf8)))
        #expect(notes.count == 2)
        #expect(notes[0].text.hasPrefix("**Courses**"))
        let expected = ISO8601DateFormatter().date(from: "2026-10-31T18:00:15Z")
        #expect(notes[1].modified == expected)
        #expect(Importer.parseTot(Data("{}".utf8)) == nil)
        #expect(Importer.parseTot(Data("pas du json".utf8)) == nil)
    }

    @Test func importKeepsDatesAndDoesNotDuplicate() throws {
        let store = NoteStore(directory: temp())
        let notes = try #require(Importer.parseTot(Data(sample.utf8)))
        let first = Importer.add(notes, to: store)
        #expect(first.added == 2 && first.alreadyPresent == 0)
        #expect(store.notes.count == 2)
        #expect(store.notes.first?.text.hasPrefix("**Courses**") == true)   // la plus récente d'abord
        let again = Importer.add(notes, to: store)
        #expect(again.added == 0 && again.alreadyPresent == 2)
        #expect(store.notes.count == 2)
        #expect(NoteStore(directory: store.directory).notes.count == 2)       // écrit sur le disque
    }

    @Test func latestBackupPicksNewestValidFile() throws {
        let dir = temp()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(sample.utf8).write(to: dir.appendingPathComponent("2026-10-10 1248.json"))
        try Data(sample.utf8).write(to: dir.appendingPathComponent("2026-11-04 1037.json"))
        try Data("cassé".utf8).write(to: dir.appendingPathComponent("2026-11-05 0000.json"))
        setenv("QNOTES_TOT_DIR", dir.path, 1)
        defer { unsetenv("QNOTES_TOT_DIR") }
        #expect(Importer.latestTotBackup()?.lastPathComponent == "2026-11-04 1037.json")
    }

    @Test func textAndMarkdownFiles() throws {
        let dir = temp()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let md = dir.appendingPathComponent("idée.md")
        try "# Idée\ntexte".write(to: md, atomically: true, encoding: .utf8)
        #expect(try Importer.notes(from: md).first?.text == "# Idée\ntexte")
        let empty = dir.appendingPathComponent("vide.txt")
        try "  ".write(to: empty, atomically: true, encoding: .utf8)
        #expect(throws: Importer.ImportError.self) { try Importer.notes(from: empty) }
    }
}
