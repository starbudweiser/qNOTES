# qNOTES

Version personnelle d'un bloc-notes à la Tot (The Iconfactory) avec les fonctions premium : notes en texte enrichi illimitées,
puces intelligentes, séparateurs personnalisés, synchro iCloud Drive, sauvegardes automatiques, actions Raccourcis,
compteur de mots, widgets. Swift/SwiftUI + AppKit (NSTextView), sans bac à sable. Code écrit de zéro : rien de Tot n'est repris.

- Interface : design system Socle. `Sources/qNOTES/Socle.swift` est recopié de Socle par `build_app.sh`, ne pas le modifier ici.
  `Updater.swift` et `UpdaterView.swift` viennent de `_tools/shared` (ne pas les modifier ici).
- Textes : `Resources/<langue>.lproj/Localizable.strings` (fr d'abord, puis en, es, it) ; un test vérifie que les clés sont les mêmes.
- Cœur testable : `Sources/qNOTESCore` (Note, NoteStore, ListTools, Backups). `swift test`.
- Données : `~/Library/Application Support/qNOTES/Notes/<id>.json` (un fichier par note) ; avec la synchro, dans
  `~/Library/Mobile Documents/com~apple~CloudDocs/qNOTES`. Sauvegardes : `…/qNOTES/Backups`. `QNOTES_DATA_DIR` et
  `QNOTES_ICLOUD_DIR` redirigent pour les essais.
- Ne jamais comparer des chemins de fichiers dans NoteStore (liens symboliques) : comparer les noms (une perte de données est déjà arrivée).
- Texte enrichi : une note = `rtf` (RTF à 16 pt, sans couleur de texte par défaut ni police du réglage) + `text` (miroir en texte simple : titre, recherche, widget, Raccourcis). `RichText.swift` : `display` applique police/taille/couleur du thème, `rtf(from:)` fait le chemin inverse, `normalizedPaste` nettoie les collages. Mise en forme : `Formatting.swift` (extension de `NoteTextView`, passe par shouldChangeText), barre/mini-barre/menu : `FormatBar.swift`. Listes = préfixes en texte (« • », « 1. », « ☐ ») gérés par `ListTools`, retrait suspendu par `RichText.fixLists`.
- Import : `qNOTESCore/Importer.swift` (sauvegardes JSON de Tot, lues dans `~/Library/Containers/com.iconfactory.Tot/…/Backups`, `QNOTES_TOT_DIR` pour les essais ; fichiers .md/.txt) ; `qNOTES --import <fichier>` en terminal.
- Anciennes notes Markdown (sans `rtf`) : converties à l'ouverture par `qNOTESCore/RichImport.swift` (testé) + `RichText.attributed(markdown:)`, enregistrées au premier changement. Police des notes : réglage `fontFamily` (`FontPicker.swift`), vide = police du système. Mini-barre = sous-vue de la zone de texte (`NoteEditor.Coordinator.showMini`). `QNOTES_CAPTURE_SELECT="début,longueur"` la montre en capture.
- Barre de menu : `MenuBar.swift` (`MenuBarController` = NSStatusItem + NSPopover, `QuickView`, `HotKey` Carbon ⌃⌥N). Réglage `displayMode` (both/menubar/dock) appliqué en direct par `AppDelegate.applyDisplay` (menubar = politique .accessory, pas de fenêtre au lancement). `EditorController.shared.textView` suit la zone de texte qui a le focus. `--capture-popover f.png` pour le volet.
- Widget : cible `Sources/qNOTESWidget` (WidgetKit, point d'entrée `_NSExtensionMain` via `unsafeFlags`), empaquetée par `build_app.sh` dans
  `Contents/PlugIns/qNOTESWidget.appex` (bac à sable + groupe `35KLMK53PN.fr.stephan.qnotes`, droits dans `assets/*.entitlements`, signés par un
  second passage après `sign_app.sh`). L'appli écrit `widget.json` dans `~/Library/Group Containers/<groupe>` (`WidgetBridge`, `WidgetShare`) ;
  `qNOTES --push-widget` le fait sans fenêtre. Clic = lien `qnotes://note/<id>`.
  `scripts/release.sh` passe `APP_ENTITLEMENTS=assets/app.entitlements` à `notarize_app.sh` (l'extension garde ses droits, `--preserve-metadata`).
- Essais sans fenêtre : `qNOTES --selftest` (comportement de la zone de texte), `qNOTES --capture f.png`, `--capture-settings f.png`, `--capture-about f.png`, `--capture-popover f.png`.
- Build et installation (dans ~/Applications/Applications Personnelles) : `./build_app.sh`. Publier : `scripts/release.sh <version>`.
