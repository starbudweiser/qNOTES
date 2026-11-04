import AppKit
import SwiftUI
import qNOTESCore

/// Libellés et syntaxe de chaque action de l'assistant Markdown.
enum MarkdownLabels {
    static func name(_ a: MarkdownAction) -> String { L("md.\(a.rawValue)") }

    /// Syntaxe montrée dans l'aide, avec le mot « texte » dans la langue de l'appli.
    static func syntax(_ a: MarkdownAction) -> String {
        let t = L("md.placeholder.text"), u = L("md.placeholder.url")
        switch a {
        case .h1: return "# \(t)"
        case .h2: return "## \(t)"
        case .h3: return "### \(t)"
        case .bold: return "**\(t)**"
        case .italic: return "*\(t)*"
        case .strike: return "~~\(t)~~"
        case .code: return "`\(t)`"
        case .link: return "[\(t)](\(u))"
        case .bullet: return "- \(t)"
        case .numbered: return "1. \(t)"
        case .task: return "- [ ] \(t)"
        case .quote: return "> \(t)"
        case .codeBlock: return "``` … ```"
        case .separator: return "---"
        }
    }

    static func icon(_ a: MarkdownAction) -> (symbol: String?, text: String?) {
        switch a {
        case .h1: (nil, "H1")
        case .h2: (nil, "H2")
        case .h3: (nil, "H3")
        case .bold: ("bold", nil)
        case .italic: ("italic", nil)
        case .strike: ("strikethrough", nil)
        case .code: ("chevron.left.forwardslash.chevron.right", nil)
        case .link: ("link", nil)
        case .bullet: ("list.bullet", nil)
        case .numbered: ("list.number", nil)
        case .task: ("checklist", nil)
        case .quote: ("text.quote", nil)
        case .codeBlock: ("curlybraces", nil)
        case .separator: ("minus", nil)
        }
    }

    static let shortcuts: [MarkdownAction: String] = [
        .h1: "⌘1", .h2: "⌘2", .h3: "⌘3", .bold: "⌘B", .italic: "⌘I", .strike: "⇧⌘X", .code: "⌥⌘C", .link: "⌘K",
        .bullet: "⇧⌘8", .numbered: "⇧⌘7", .task: "⇧⌘T", .quote: "⇧⌘9",
    ]
}

/// Relie la barre de format, le menu Format et l'aide à la zone de texte ouverte.
@MainActor
final class EditorController: ObservableObject {
    static let shared = EditorController()
    weak var textView: NoteTextView?
    @Published var helpShown = false
    /// Mises en forme actives sous le curseur : leurs boutons sont allumés.
    @Published var active: Set<MarkdownAction> = []

    func apply(_ action: MarkdownAction) {
        guard let view = textView else { return }
        let context = MarkdownAssistant.Context(glyph: Prefs.glyph, separator: Prefs.separatorText,
                                                textPlaceholder: L("md.placeholder.text"), urlPlaceholder: L("md.placeholder.url"))
        let edit = MarkdownAssistant.edit(action, in: view.string, selection: view.selectedRange(), context: context)
        view.window?.makeFirstResponder(view)
        view.apply(edit)
    }

    /// Couleur du texte sélectionné (nil : retire la couleur).
    func applyColor(_ hex: String?) {
        guard let view = textView else { return }
        let context = MarkdownAssistant.Context(glyph: Prefs.glyph, separator: Prefs.separatorText,
                                                textPlaceholder: L("md.placeholder.text"), urlPlaceholder: L("md.placeholder.url"))
        let edit = MarkdownAssistant.color(hex, in: view.string, selection: view.selectedRange(), context: context)
        view.window?.makeFirstResponder(view)
        view.apply(edit)
    }

    func showHelp() { helpShown = true }
}

extension Color {
    /// « RRGGBB » (avec ou sans #).
    init(hex: String) {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xFFFFFF
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// Pastilles de couleur du texte + « sans couleur ».
struct ColorSwatches: View {
    var size: CGFloat = 16
    let pick: (String?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MarkdownAssistant.palette, id: \.self) { hex in
                Circle().fill(Color(hex: hex)).frame(width: size, height: size)
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .contentShape(Circle())
                    .onTapGesture { pick(hex) }
                    .help(L("md.color"))
            }
            Image(systemName: "circle.slash").font(.system(size: size - 1)).foregroundStyle(Socle.C.textMuted)
                .contentShape(Circle())
                .onTapGesture { pick(nil) }
                .help(L("md.color.none"))
        }
    }
}

// MARK: Barre de format

struct FormatBar: View {
    @ObservedObject private var controller = EditorController.shared
    @State private var colorsShown = false
    private let groups: [[MarkdownAction]] = [
        [.h1, .h2, .h3], [.bold, .italic, .strike, .code, .link], [.bullet, .numbered, .task], [.quote, .codeBlock, .separator],
    ]

    var body: some View {
        HStack(spacing: Socle.M.space1) {
            ForEach(groups.indices, id: \.self) { index in
                if index > 0 { Rectangle().fill(Socle.C.border).frame(width: 1, height: 16).padding(.horizontal, Socle.M.space1) }
                ForEach(groups[index], id: \.self) { action in
                    FormatButton(action: action, active: controller.active.contains(action)) { controller.apply(action) }
                }
            }
            Rectangle().fill(Socle.C.border).frame(width: 1, height: 16).padding(.horizontal, Socle.M.space1)
            Button { colorsShown.toggle() } label: { Image(systemName: "paintpalette").font(.system(size: 13)) }
                .buttonStyle(SocleButtonStyle(.tertiary, height: 28)).frame(width: 34)
                .help(L("md.color"))
                .popover(isPresented: $colorsShown, arrowEdge: .bottom) {
                    ColorSwatches(size: 20) { controller.applyColor($0); colorsShown = false }.padding(Socle.M.space3)
                }
            Spacer(minLength: Socle.M.space2)
            Button { controller.helpShown.toggle() } label: {
                Image(systemName: "questionmark.circle").font(.system(size: 14))
            }
            .buttonStyle(SocleButtonStyle(.tertiary, height: 28))
            .frame(width: 34)
            .help(L("md.help.title"))
            .accessibilityLabel(L("md.help.title"))
            .popover(isPresented: $controller.helpShown, arrowEdge: .bottom) { MarkdownHelp(controller: controller) }
        }
        .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space1_5)
        .background(Socle.C.surfaceRaised)
    }
}

private struct FormatButton: View {
    let action: MarkdownAction
    var active = false
    let perform: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: perform) {
            let icon = MarkdownLabels.icon(action)
            Group {
                if let symbol = icon.symbol { Image(systemName: symbol).font(.system(size: 13)) }
                else if let text = icon.text { Text(text).font(.system(size: 12, weight: .bold)) }
            }
            .foregroundStyle(active ? Socle.C.accentText : hover ? Socle.C.textStrong : Socle.C.textMuted)
            .frame(width: 30, height: 28)
            .background(active ? Socle.C.controlStrong : hover ? Socle.C.control : .clear, in: RoundedRectangle(cornerRadius: Socle.M.radius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(tooltip)
        .accessibilityLabel(MarkdownLabels.name(action))
    }

    private var tooltip: String {
        var text = "\(MarkdownLabels.name(action)) — \(MarkdownLabels.syntax(action))"
        if let key = MarkdownLabels.shortcuts[action] { text += "  \(key)" }
        return text
    }
}

// MARK: Aide : balises Markdown

struct MarkdownHelp: View {
    let controller: EditorController

    private let sections: [(String, [MarkdownAction])] = [
        ("help.group.text", [.bold, .italic, .strike, .code, .link]),
        ("help.group.structure", [.h1, .h2, .h3, .quote, .codeBlock, .separator]),
        ("help.group.lists", [.bullet, .numbered, .task]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Socle.M.space4) {
                VStack(alignment: .leading, spacing: Socle.M.space1) {
                    Text(L("md.help.title")).socle(Socle.T.title).foregroundStyle(Socle.C.textStrong)
                    Text(L("md.help.intro")).socle(Socle.T.body).foregroundStyle(Socle.C.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(sections, id: \.0) { key, actions in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L(key).uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
                            .padding(.bottom, Socle.M.space1)
                        ForEach(actions, id: \.self) { action in
                            HelpRow(action: action) {
                                controller.helpShown = false
                                controller.apply(action)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: Socle.M.space1_5) {
                    Text(L("help.group.tips").uppercased()).socle(Socle.T.eyebrow).foregroundStyle(Socle.C.textMuted)
                    Text(L("help.tip.bullets")).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                    Text(L("help.tip.separator")).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                    Text(L("help.tip.plain")).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Socle.M.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 380, height: 520)
        .background(Socle.C.surface)
    }
}

private struct HelpRow: View {
    let action: MarkdownAction
    let perform: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: perform) {
            HStack(spacing: Socle.M.space3) {
                Text(MarkdownLabels.name(action)).socle(Socle.T.body).foregroundStyle(Socle.C.text)
                Spacer(minLength: Socle.M.space2)
                Text(MarkdownLabels.syntax(action)).socle(Socle.T.mono).foregroundStyle(Socle.C.accentText)
                    .padding(.horizontal, Socle.M.space2).padding(.vertical, 2)
                    .background(Socle.C.bgSunken, in: RoundedRectangle(cornerRadius: Socle.M.radius))
            }
            .padding(.horizontal, Socle.M.space2).padding(.vertical, Socle.M.space1_5)
            .background(hover ? Socle.C.surfaceHover : .clear, in: RoundedRectangle(cornerRadius: Socle.M.radius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Mini-barre flottante près du texte sélectionné

struct MiniToolbar: View {
    @ObservedObject var controller: EditorController
    private let actions: [MarkdownAction] = [.bold, .italic, .strike, .code, .link, .h2, .bullet, .quote]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(actions, id: \.self) { action in
                    MiniButton(action: action, active: controller.active.contains(action)) { controller.apply(action) }
                }
            }
            ColorSwatches(size: 15) { controller.applyColor($0) }.padding(.bottom, 3)
        }
        .padding(3)
        .background(Socle.C.surfaceRaised, in: RoundedRectangle(cornerRadius: Socle.M.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Socle.M.radiusMd).stroke(Socle.C.borderStrong, lineWidth: 1))
        .fixedSize()
    }
}

private struct MiniButton: View {
    let action: MarkdownAction
    let active: Bool
    let perform: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: perform) {
            let icon = MarkdownLabels.icon(action)
            Group {
                if let symbol = icon.symbol { Image(systemName: symbol).font(.system(size: 12)) }
                else if let text = icon.text { Text(text).font(.system(size: 11, weight: .bold)) }
            }
            .foregroundStyle(active ? Socle.C.accentText : Socle.C.textStrong)
            .frame(width: 28, height: 26)
            .background(active ? Socle.C.controlStrong : hover ? Socle.C.control : .clear, in: RoundedRectangle(cornerRadius: Socle.M.radius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(MarkdownLabels.name(action) + " — " + MarkdownLabels.syntax(action))
    }
}
