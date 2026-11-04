import SwiftUI
import WidgetKit
import qNOTESCore

struct NotesEntry: TimelineEntry {
    let date: Date
    let notes: [WidgetNote]
}

struct NotesProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotesEntry {
        NotesEntry(date: Date(), notes: [
            WidgetNote(id: UUID(), title: "qNOTES", lines: ["Markdown", "Sync iCloud"], modified: Date(), pinned: true),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (NotesEntry) -> Void) {
        completion(NotesEntry(date: Date(), notes: WidgetShare.read()?.notes ?? placeholder(in: context).notes))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NotesEntry>) -> Void) {
        let entry = NotesEntry(date: Date(), notes: WidgetShare.read()?.notes ?? [])
        // L'appli demande un rafraîchissement à chaque modification ; ce délai n'est qu'un filet de sécurité.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

/// Couleurs Socle (fond sombre par défaut, clair si le système l'est).
struct Palette {
    let dark: Bool
    var background: Color { dark ? Color(red: 0.118, green: 0.118, blue: 0.118) : Color(red: 0.949, green: 0.949, blue: 0.949) }
    var strong: Color { dark ? .white : Color(red: 0.067, green: 0.067, blue: 0.067) }
    var text: Color { dark ? Color(white: 0.867) : Color(white: 0.133) }
    var muted: Color { dark ? Color(white: 0.667) : Color(white: 0.333) }
    var accent: Color { dark ? Color(red: 0.22, green: 0.74, blue: 0.97) : Color(red: 0.012, green: 0.412, blue: 0.631) }
    var border: Color { dark ? Color(white: 0.2) : Color(white: 0.83) }
}

struct NoteBlock: View {
    let note: WidgetNote
    let lineLimit: Int
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if note.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(palette.accent) }
                Text(note.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.strong).lineLimit(2)
            }
            ForEach(Array(note.lines.prefix(lineLimit).enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 12)).foregroundStyle(palette.text).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NotesWidgetView: View {
    let entry: NotesEntry
    /// Pour dessiner une taille précise hors du système (essais).
    var familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var systemFamily
    private var family: WidgetFamily { familyOverride ?? systemFamily }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette(dark: scheme == .dark)
        Group {
            if entry.notes.isEmpty {
                Text("widget.empty").font(.system(size: 12)).foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).multilineTextAlignment(.center)
            } else {
                switch family {
                case .systemSmall:
                    NoteBlock(note: entry.notes[0], lineLimit: 5, palette: palette)
                case .systemMedium:
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(entry.notes.prefix(2)) { note in
                            Link(destination: WidgetShare.url(for: note.id)) { NoteBlock(note: note, lineLimit: 5, palette: palette) }
                        }
                        if entry.notes.count < 2 { Spacer(minLength: 0) }
                    }
                default:
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(entry.notes.prefix(4)) { note in
                            Link(destination: WidgetShare.url(for: note.id)) { NoteBlock(note: note, lineLimit: 2, palette: palette) }
                            if note.id != entry.notes.prefix(4).last?.id { Rectangle().fill(palette.border).frame(height: 1) }
                        }
                    }
                }
            }
        }
        .widgetURL(entry.notes.first.map { WidgetShare.url(for: $0.id) })
        .containerBackground(for: .widget) { palette.background }
    }
}

struct QNotesWidget: Widget {
    let kind = "fr.stephan.qnotes.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NotesProvider()) { entry in
            NotesWidgetView(entry: entry)
        }
        .configurationDisplayName("widget.name")
        .description("widget.desc")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct QNotesWidgetBundle: WidgetBundle {
    var body: some Widget { QNotesWidget() }
}
