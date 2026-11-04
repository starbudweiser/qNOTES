import AppKit
import SwiftUI

/// Bouton « police » des réglages : ouvre la liste des familles installées, chacune écrite dans sa propre police.
struct FontPickerButton: View {
    @Binding var family: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            HStack(spacing: Socle.M.space2) {
                Text(family.isEmpty ? L("set.font.system") : family)
                    .font(Font(RichText.font(family: family, size: 13) as CTFont))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
            }
        }
        .buttonStyle(SocleButtonStyle(.secondary)).fixedSize()
        .popover(isPresented: $shown, arrowEdge: .bottom) { FontList(family: $family) { shown = false } }
    }
}

private struct FontList: View {
    @Binding var family: String
    let close: () -> Void
    @State private var query = ""

    private static let families: [String] = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }

    private var shown: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? Self.families : Self.families.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(L("search.placeholder"), text: $query).socleField().padding(Socle.M.space2)
            Rectangle().fill(Socle.C.border).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if query.isEmpty { row("", L("set.font.system")) }
                        ForEach(shown, id: \.self) { name in row(name, name) }
                    }
                    .padding(Socle.M.space1)
                }
                .onAppear { proxy.scrollTo(family, anchor: .center) }
            }
        }
        .frame(width: 300, height: 380)
        .background(Socle.C.surface)
    }

    private func row(_ value: String, _ title: String) -> some View {
        Button { family = value; close() } label: {
            HStack {
                Text(title).font(Font(RichText.font(family: value, size: 15) as CTFont)).foregroundStyle(Socle.C.textStrong)
                Spacer(minLength: 0)
                if value == family { Image(systemName: "checkmark").font(.system(size: 11)).foregroundStyle(Socle.C.accentText) }
            }
            .padding(.horizontal, Socle.M.space2).padding(.vertical, 5)
            .background(value == family ? Socle.C.surfaceSelected : .clear, in: RoundedRectangle(cornerRadius: Socle.M.radius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(value)
    }
}
