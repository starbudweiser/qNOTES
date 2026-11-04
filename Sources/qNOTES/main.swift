import AppKit
import qNOTESCore

let arguments = CommandLine.arguments

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.regular)

/// `--capture <fichier.png>`, `--capture-about`, `--capture-settings` : rendu hors écran pour vérifier l'interface
/// sans ouvrir de fenêtre devant le travail en cours.
for (flag, render) in [("--capture", Capture.main), ("--capture-about", Capture.about), ("--capture-settings", Capture.settings)] {
    if let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) {
        let path = arguments[index + 1]
        app.setActivationPolicy(.prohibited)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            MainActor.assumeIsolated { render(delegate, path) }
        }
    }
}

app.run()
