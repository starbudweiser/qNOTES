import AppKit
import WidgetKit
import qNOTESCore

let arguments = CommandLine.arguments

if arguments.contains("--selftest") { MainActor.assumeIsolated { _ = NSApplication.shared; SelfTest.run() } }

/// `--import <fichier>` : import sans interface (sauvegarde Tot .json, .md, .txt), pour le terminal et les essais.
if let flag = arguments.firstIndex(of: "--import"), arguments.indices.contains(flag + 1) {
    MainActor.assumeIsolated {
        let store = NoteStore(directory: NoteStore.localDirectory)
        do {
            let report = Importer.add(try Importer.notes(from: URL(fileURLWithPath: arguments[flag + 1])), to: store)
            print("\(report.added) notes importées, \(report.alreadyPresent) déjà présentes")
            exit(0)
        } catch {
            print("Import impossible : \(error)")
            exit(1)
        }
    }
}

/// `--push-widget` : met à jour le widget à partir des vraies notes, sans fenêtre (terminal, essais).
if arguments.contains("--push-widget") {
    MainActor.assumeIsolated {
        let store = NoteStore(directory: (Prefs.sync ? NoteStore.iCloudDirectory : nil) ?? NoteStore.localDirectory)
        let snapshot = WidgetShare.snapshot(from: store.notes)
        WidgetShare.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        print("Widget : \(snapshot.notes.count) notes envoyées vers \(WidgetShare.directory.path)")
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)

/// `--capture <fichier.png>`, `--capture-about`, `--capture-settings` : rendu hors écran pour vérifier l'interface
/// sans ouvrir de fenêtre devant le travail en cours.
for (flag, render) in [("--capture", Capture.main), ("--capture-about", Capture.about), ("--capture-settings", Capture.settings), ("--capture-help", Capture.help), ("--capture-popover", Capture.popover)] {
    if let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) {
        let path = arguments[index + 1]
        app.setActivationPolicy(.prohibited)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            MainActor.assumeIsolated { render(delegate, path) }
        }
    }
}

app.run()
