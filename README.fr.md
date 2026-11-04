# qNOTES

[English](README.md)

Bloc-notes Markdown personnel pour macOS, inspiré de Tot (The Iconfactory), sans lien avec ses auteurs.

## Fonctions

- **Notes illimitées en Markdown**, affichées avec la mise en forme en direct : titres, gras, italique, barré, code, citations, liens, tâches.
- **Import depuis Tot** : Fichier > Importer des notes… lit la dernière sauvegarde de Tot (Tot n'est pas modifié) ou tout fichier `.json`, `.md`, `.txt` ; les dates sont conservées, aucun doublon.
- **Mode Mise en page** : les balises sont masquées hors de la ligne en cours, on voit le résultat ; une mini-barre flottante apparaît au-dessus du texte sélectionné, et les boutons de la barre s'allument selon le style sous le curseur.
- **Assistant Markdown** : barre de format, menu Format avec raccourcis (⌘B, ⌘I, ⌘K…) et aide qui liste chaque balise ; un clic sur une ligne l'applique à la sélection, un second clic la retire.
- **Puces intelligentes** : Retour continue la liste, une puce vide la termine, Tab et Maj-Tab décalent, `[]` crée une tâche, un clic sur `[ ]` la coche. La puce se choisit dans les réglages.
- **Séparateurs personnalisés** : `---` puis Retour donne le séparateur choisi (ou le vôtre).
- **Compteur de mots et de caractères**, pour la note ou la sélection.
- **Synchro iCloud Drive** : les notes sont dans `iCloud Drive/qNOTES`, un fichier par note, la modification la plus récente gagne.
- **Sauvegardes automatiques**, avec restauration (les notes actuelles sont d'abord sauvegardées).
- **Mise à jour automatique** depuis les releases GitHub (signature et notarisation vérifiées).
- Quatre langues (français, anglais, espagnol, italien), d'après la langue du système.

## Compiler

```bash
swift test
./build_app.sh        # compile, signe et installe qNOTES.app
```

Données : `~/Library/Application Support/qNOTES/` (`QNOTES_DATA_DIR` pour les essais).
