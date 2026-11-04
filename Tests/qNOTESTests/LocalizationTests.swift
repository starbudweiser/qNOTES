import Foundation
import Testing

@Suite struct LocalizationTests {
    static func keys(_ lang: String) throws -> Set<String> {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("Resources/\(lang).lproj/Localizable.strings"), encoding: .utf8)
        return Set(text.split(separator: "\n").filter { $0.hasPrefix("\"") }.compactMap { $0.split(separator: "\"", omittingEmptySubsequences: true).first.map(String.init) })
    }

    @Test func allLanguagesHaveTheSameKeys() throws {
        let fr = try Self.keys("fr")
        #expect(fr.count > 50)
        for lang in ["en", "es", "it"] { #expect(try Self.keys(lang) == fr, "\(lang)") }
    }
}
