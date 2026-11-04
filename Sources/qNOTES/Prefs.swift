import Foundation
import qNOTESCore

/// Réglages de l'appli (UserDefaults). Les vues les lisent aussi avec @AppStorage, sous les mêmes clés.
enum Prefs {
    static let fontSize = "fontSize"
    static let smartBullets = "smartBullets"
    static let bulletGlyph = "bulletGlyph"
    static let separator = "separator"
    static let backupEnabled = "backupEnabled"
    static let backupKeep = "backupKeep"
    static let backupHours = "backupHours"
    static let syncICloud = "syncICloud"
    static let autoUpdate = "autoUpdate"
    static let theme = "theme"
    static let fontFamily = "fontFamily"

    static let displayMode = "displayMode"
    static let hotkeyEnabled = "hotkeyEnabled"

    /// Où vit l'appli : « dock », « menubar » (icône dans la barre de menu seulement) ou « both ».
    static let displayModes = ["both", "menubar", "dock"]

    static let defaultFontSize = 16.0

    static var defaults: UserDefaults { .standard }

    static var size: CGFloat { CGFloat(defaults.object(forKey: fontSize) as? Double ?? defaultFontSize) }
    static var smart: Bool { defaults.object(forKey: smartBullets) as? Bool ?? true }
    static var glyph: String { defaults.string(forKey: bulletGlyph) ?? "•" }
    /// Famille de police des notes (vide : police du système).
    static var family: String { defaults.string(forKey: fontFamily) ?? "" }
    static var separatorText: String { defaults.string(forKey: separator) ?? Separators.presets[0] }
    static var backups: Bool { defaults.object(forKey: backupEnabled) as? Bool ?? true }
    static var keep: Int { defaults.object(forKey: backupKeep) as? Int ?? 30 }
    static var hours: Int { defaults.object(forKey: backupHours) as? Int ?? 1 }
    static var display: String {
        let value = defaults.string(forKey: displayMode) ?? "both"
        return displayModes.contains(value) ? value : "both"
    }
    static var hotkey: Bool { defaults.object(forKey: hotkeyEnabled) as? Bool ?? true }
    static var sync: Bool { defaults.object(forKey: syncICloud) as? Bool ?? false }
}
