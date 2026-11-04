# qNOTES

[English](README.md)

Bloc-notes personnel en texte enrichi pour macOS, inspiré de Tot (The Iconfactory), sans lien avec ses auteurs.

## Fonctions

- **Notes illimitées en texte enrichi** : titres, gras, italique, souligné, barré, couleurs, alignement, listes à puces / numérotées / de tâches, liens. Les notes sont enregistrées en RTF avec un miroir en texte simple.
- **Import depuis Tot** : Fichier > Importer des notes… lit la dernière sauvegarde de Tot (Tot n'est pas modifié) ou tout fichier `.json`, `.md`, `.txt` ; les dates sont conservées, aucun doublon.
- **Choix de la police** : Réglages > Écriture permet de choisir la police (toute famille installée, aperçue dans sa propre police) et la taille du texte pour toutes les notes.
- **Outils de mise en page classiques** : barre d'outils, menu Format avec les raccourcis habituels (⌘B, ⌘I, ⌘U, ⌘K…) et mini-barre flottante au-dessus du texte sélectionné ; les boutons s'allument selon le style sous le curseur. Les anciennes notes Markdown sont converties à l'ouverture.
- **Puces intelligentes** : Retour continue la liste, une puce vide la termine, Tab et Maj-Tab décalent, `[]` crée une tâche, un clic sur sa case la coche. La puce se choisit dans les réglages.
- **Séparateurs personnalisés** : `---` puis Retour donne le séparateur choisi (ou le vôtre).
- **Compteur de mots et de caractères**, pour la note ou la sélection.
- **Synchro iCloud Drive** : les notes sont dans `iCloud Drive/qNOTES`, un fichier par note, la modification la plus récente gagne.
- **Sauvegardes automatiques**, avec restauration (les notes actuelles sont d'abord sauvegardées).
- **Volet de la barre de menu** : une icône ouvre un volet de notes rapide (pastilles de couleur pour les dernières notes, éditeur, compteurs) ; raccourci global ⌃⌥N ; Dock, barre de menu ou les deux dans les réglages.
- **Widget** (petit, moyen, grand) : vos notes épinglées ou les plus récentes sur le bureau ; un clic ouvre la note.
- **Mise à jour automatique** depuis les releases GitHub (signature et notarisation vérifiées).
- Quatre langues (français, anglais, espagnol, italien), d'après la langue du système.

## Compiler

```bash
swift test
./build_app.sh        # compile, signe et installe qNOTES.app
```

Données : `~/Library/Application Support/qNOTES/` (`QNOTES_DATA_DIR` pour les essais).
