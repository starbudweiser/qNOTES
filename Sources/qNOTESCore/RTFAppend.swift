import Foundation

/// Ajoute des paragraphes à la fin d'un document RTF sans passer par AppKit (Raccourcis, ligne de commande).
public enum RTFAppend {
    public static func append(text: String, to rtf: Data) -> Data? {
        guard var body = String(data: rtf, encoding: .utf8) ?? String(data: rtf, encoding: .isoLatin1),
              let close = body.lastIndex(of: "}") else { return nil }
        var piece = ""
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            piece += (index == 0 ? "\\plain " : "\\par\\pard\\plain ") + escape(String(line))
        }
        body.insert(contentsOf: piece + "\n", at: close)
        return body.data(using: .utf8)
    }

    static func escape(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "{": out += "\\{"
            case "}": out += "\\}"
            default:
                if scalar.value < 128 { out.unicodeScalars.append(scalar) }
                else { for unit in String(scalar).utf16 { out += "\\u\(Int16(bitPattern: unit))?" } }
            }
        }
        return out
    }
}
