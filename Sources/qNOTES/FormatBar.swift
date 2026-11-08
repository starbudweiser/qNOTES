import AppKit
import SwiftUI
import qNOTESCore

/// Actions de la barre de mise en forme et du menu Format.
enum FormatAction: String, CaseIterable, Hashable {
    case title, subtitle, body
    case bold, italic, underline, strike
    case alignLeft, alignCenter, alignRight
    case bullet, numbered, task
    case link, separator
}

enum FormatLabels {
    static func name(_ a: FormatAction) -> String { L("fmt.\(a.rawValue)") }

    static func icon(_ a: FormatAction) -> String {
        switch a {
        case .title, .subtitle, .body: "textformat.size"
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strike: "strikethrough"
        case .alignLeft: "text.alignleft"
        case .alignCenter: "text.aligncenter"
        case .alignRight: "text.alignright"
        case .bullet: "list.bullet"
        case .numbered: "list.number"
        case .task: "checklist"
        case .link: "link"
        case .separator: "minus"
        }
    }

    static let shortcuts: [FormatAction: String] = [
        .title: "⌘1", .subtitle: "⌘2", .body: "⌘0", .bold: "⌘B", .italic: "⌘I", .underline: "⌘U", .strike: "⇧⌘X",
        .alignLeft: "⌘{", .alignCenter: "⌘|", .alignRight: "⌘}", .bullet: "⇧⌘8", .numbered: "⇧⌘7", .task: "⇧⌘T", .link: "⌘K",
    ]
}

/// Relie la barre de format et le menu Format à la zone de texte qui a le focus.
@MainActor
final class EditorController: ObservableObject {
    static let shared = EditorController()
    weak var textView: NoteTextView?
    /// Mises en forme actives sous le curseur : leurs boutons sont allumés.
    @Published var active: Set<FormatAction> = []

    func apply(_ action: FormatAction) {
        guard let view = textView else { return }
        view.window?.makeFirstResponder(view)
        view.format(action)
        refresh()
    }

    /// Couleur du texte sélectionné (nil : retire la couleur).
    func applyColor(_ hex: String?) {
        guard let view = textView else { return }
        view.window?.makeFirstResponder(view)
        view.setColor(hex)
    }

    func refresh() { active = textView?.activeFormats() ?? [] }
}

/// Pastilles de couleur du texte + « sans couleur ».
struct ColorSwatches: View {
    var size: CGFloat = 16
    let pick: (String?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RichText.palette, id: \.self) { hex in
                Circle().fill(Color(hex: hex)).frame(width: size, height: size)
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .contentShape(Circle())
                    .onTapGesture { pick(hex) }
                    .help(L("fmt.color"))
            }
            Image(systemName: "circle.slash").font(.system(size: size - 1)).foregroundStyle(Socle.C.textMuted)
                .contentShape(Circle())
                .onTapGesture { pick(nil) }
                .help(L("fmt.color.none"))
        }
    }
}

// MARK: Barre de format

struct FormatBar: View {
    @ObservedObject private var controller = EditorController.shared
    @State private var colorsShown = false
    private let groups: [[FormatAction]] = [
        [.bold, .italic, .underline, .strike], [.alignLeft, .alignCenter, .alignRight], [.bullet, .numbered, .task], [.link, .separator],
    ]
    private let styles: [FormatAction] = [.title, .subtitle, .body]

    private var currentStyle: FormatAction { styles.first(where: controller.active.contains) ?? .body }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Socle.M.space1) {
                Menu {
                    ForEach(styles, id: \.self) { style in
                        Button(FormatLabels.name(style) + "  " + (FormatLabels.shortcuts[style] ?? "")) { controller.apply(style) }
                    }
                } label: {
                    Text(FormatLabels.name(currentStyle)).socle(Socle.T.label).foregroundStyle(Socle.C.textStrong)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help(L("fmt.style"))
                .padding(.trailing, Socle.M.space1)
                ForEach(groups.indices, id: \.self) { index in
                    Rectangle().fill(Socle.C.border).frame(width: 1, height: 16).padding(.horizontal, Socle.M.space1)
                    if index == 1 {
                        Button { colorsShown.toggle() } label: { Image(systemName: "paintpalette").font(.system(size: 13)) }
                            .buttonStyle(SocleButtonStyle(.tertiary, height: 28)).frame(width: 34)
                            .help(L("fmt.color"))
                            .popover(isPresented: $colorsShown, arrowEdge: .bottom) {
                                ColorSwatches(size: 20) { controller.applyColor($0); colorsShown = false }.padding(Socle.M.space3)
                            }
                    }
                    ForEach(groups[index], id: \.self) { action in
                        FormatButton(action: action, active: controller.active.contains(action)) { controller.apply(action) }
                    }
                }
            }
            .padding(.horizontal, Socle.M.space3).padding(.vertical, Socle.M.space1_5)
        }
        .surfaceBackground(Socle.C.surfaceRaised)
    }
}

private struct FormatButton: View {
    let action: FormatAction
    var active = false
    let perform: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: perform) {
            Image(systemName: FormatLabels.icon(action)).font(.system(size: 13))
                .foregroundStyle(active ? Socle.C.accentText : hover ? Socle.C.textStrong : Socle.C.textMuted)
                .frame(width: 30, height: 28)
                .background(active ? Socle.C.controlStrong : hover ? Socle.C.control : .clear, in: RoundedRectangle(cornerRadius: Socle.M.radius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(tooltip)
        .accessibilityLabel(FormatLabels.name(action))
    }

    private var tooltip: String {
        var text = FormatLabels.name(action)
        if let key = FormatLabels.shortcuts[action] { text += "  \(key)" }
        return text
    }
}

// MARK: Mini-barre flottante près du texte sélectionné

struct MiniToolbar: View {
    @ObservedObject var controller: EditorController
    private let actions: [FormatAction] = [.bold, .italic, .underline, .strike, .link, .subtitle, .bullet]

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
    let action: FormatAction
    let active: Bool
    let perform: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: perform) {
            Image(systemName: FormatLabels.icon(action)).font(.system(size: 12))
                .foregroundStyle(active ? Socle.C.accentText : Socle.C.textStrong)
                .frame(width: 28, height: 26)
                .background(active ? Socle.C.controlStrong : hover ? Socle.C.control : .clear, in: RoundedRectangle(cornerRadius: Socle.M.radius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(FormatLabels.name(action))
    }
}
