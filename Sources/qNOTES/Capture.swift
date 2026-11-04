import AppKit
import SwiftUI

/// Rendus hors écran : aucune fenêtre n'apparaît et l'appli quitte aussitôt.
@MainActor
enum Capture {
    static func main(_ delegate: AppDelegate, _ path: String) {
        let window = delegate.makeMainWindow()
        guard let view = window.contentView else { exit(1) }
        window.appearance = NSAppearance(named: .darkAqua)
        render(view, size: NSSize(width: 980, height: 660), path)
    }

    static func settings(_ delegate: AppDelegate, _ path: String) {
        let actions = SettingsActions(applySync: {}, backupNow: { false }, restore: { _ in false }, checkUpdates: {})
        let view = NSHostingView(rootView: SettingsView(actions: actions))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        render(view, size: NSSize(width: 560, height: 640), path)
    }

    static func help(_ delegate: AppDelegate, _ path: String) {
        let view = NSHostingView(rootView: MarkdownHelp(controller: EditorController.shared))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        render(view, size: NSSize(width: 380, height: 520), path)
    }

    static func about(_ delegate: AppDelegate, _ path: String) {
        let window = About.makeWindow()
        window.appearance = NSAppearance(named: .darkAqua)
        if let view = window.contentView {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor(white: 0.17, alpha: 1).cgColor
            render(view, size: view.frame.size, path)
        }
    }

    private static func render(_ view: NSView, size: NSSize, _ path: String) {
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                exit(0)
            }
        }
    }
}
