import Foundation
import qNOTESCore

/// Réglages de l'appli (UserDefaults). Les vues les lisent aussi avec @AppStorage, sous les mêmes clés.
enum Prefs {
    static let fontSize = "fontSize"
    static let smartBullets = "smartBullets"
    static let bulletGlyph = "bulletGlyph"
    static let separator = "separator"
    static let backupEnabled = "backupEnabled"
    static let syncICloud = "syncICloud"
    static let autoUpdate = "autoUpdate"
    static let theme = "theme"
    static let fontFamily = "fontFamily"
    static let monospaced = "monospaced"
    static let translucent = "translucent"
    static let stayOnTop = "stayOnTop"

    static let displayMode = "displayMode"
    static let hotkeyEnabled = "hotkeyEnabled"
    static let dotNumbers = "dotNumbers"
    static let panelMode = "panelMode"

    /// Où vit l'appli : « dock », « menubar » (icône dans la barre de menu seulement) ou « both ».
    static let displayModes = ["both", "menubar", "dock"]

    /// Volet de la barre de menu : « auto » (se ferme dès qu'on clique ailleurs), « front » (reste affiché, devant les autres fenêtres), « back » (reste affiché, derrière).
    static let panelModes = ["auto", "front", "back"]

    static let defaultFontSize = 16.0

    static var defaults: UserDefaults { .standard }

    static var size: CGFloat { CGFloat(defaults.object(forKey: fontSize) as? Double ?? defaultFontSize) }
    static var smart: Bool { defaults.object(forKey: smartBullets) as? Bool ?? true }
    static var glyph: String { defaults.string(forKey: bulletGlyph) ?? "•" }
    /// Famille de police des notes (vide : police du système).
    static var family: String { mono ? RichText.monoFamily : defaults.string(forKey: fontFamily) ?? "" }
    static var mono: Bool { defaults.object(forKey: monospaced) as? Bool ?? false }
    static var translucentWindow: Bool { defaults.object(forKey: translucent) as? Bool ?? false }
    static var onTop: Bool { defaults.object(forKey: stayOnTop) as? Bool ?? false }
    static var separatorText: String { defaults.string(forKey: separator) ?? Separators.presets[0] }
    static var backups: Bool { defaults.object(forKey: backupEnabled) as? Bool ?? true }
    /// Sauvegarde automatique : une par jour, les dix dernières sont conservées.
    static let backupEveryHours = 24
    static let backupKept = 10
    static var display: String {
        let value = defaults.string(forKey: displayMode) ?? "both"
        return displayModes.contains(value) ? value : "both"
    }
    static var panel: String {
        let value = defaults.string(forKey: panelMode) ?? "auto"
        return panelModes.contains(value) ? value : "auto"
    }
    static var hotkey: Bool { defaults.object(forKey: hotkeyEnabled) as? Bool ?? true }
    static var sync: Bool { defaults.object(forKey: syncICloud) as? Bool ?? false }
}
