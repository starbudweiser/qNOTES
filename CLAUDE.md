# qNOTES

Version personnelle d'un bloc-notes à la Tot (The Iconfactory) avec les fonctions premium : notes Markdown illimitées,
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
- Assistant Markdown : logique pure dans `qNOTESCore/MarkdownAssistant.swift` (testée), branchée par `MarkdownAssist.swift` (barre, aide, menu Format).
- Import : `qNOTESCore/Importer.swift` (sauvegardes JSON de Tot, lues dans `~/Library/Containers/com.iconfactory.Tot/…/Backups`, `QNOTES_TOT_DIR` pour les essais ; fichiers .md/.txt) ; `qNOTES --import <fichier>` en terminal.
- Mode Mise en page : `MarkdownStyler` masque les balises (police de 1 pt, transparente) sauf sur la ligne active ; mini-barre = sous-vue de la zone de texte (`NoteEditor.Coordinator.showMini`). `QNOTES_CAPTURE_SELECT="début,longueur"` la montre en capture.
- Essais sans fenêtre : `qNOTES --selftest` (comportement de la zone de texte), `qNOTES --capture f.png`, `--capture-settings f.png`, `--capture-about f.png`.
- Build et installation (dans ~/Applications/Applications Personnelles) : `./build_app.sh`. Publier : `scripts/release.sh <version>`.
