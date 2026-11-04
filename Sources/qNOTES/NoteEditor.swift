import AppKit
import SwiftUI
import qNOTESCore

/// Zone de texte : puces intelligentes, séparateurs personnalisés, cases à cocher cliquables.
final class NoteTextView: NSTextView {
    func replace(_ range: NSRange, _ string: String) {
        if shouldChangeText(in: range, replacementString: string) {
            replaceCharacters(in: range, with: string)
            didChangeText()
        }
    }

    /// Deux zones de texte peuvent coexister (fenêtre et volet de la barre de menu) : la barre de format agit sur celle qui a le focus.
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { EditorController.shared.textView = self }
        return ok
    }

    private var currentLine: (range: NSRange, text: String) {
        let ns = string as NSString
        let range = ns.lineRange(for: NSRange(location: min(selectedRange().location, ns.length), length: 0))
        var text = ns.substring(with: range)
        if text.hasSuffix("\n") { text.removeLast() }
        return (range, text)
    }

    /// Collage : le texte enrichi prend la police, la taille et les couleurs neutres du réglage.
    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        var pasted: NSAttributedString?
        if let data = board.data(forType: .rtf) { pasted = NSAttributedString(rtf: data, documentAttributes: nil) }
        else if let data = board.data(forType: .html) { pasted = NSAttributedString(html: data, documentAttributes: nil) }
        else if let text = board.string(forType: .string) { pasted = NSAttributedString(string: text) }
        guard let pasted else { super.paste(sender); return }
        let normalized = RichText.normalizedPaste(pasted, family: Prefs.family, size: Prefs.size)
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: normalized.string) else { return }
        textStorage?.replaceCharacters(in: range, with: normalized)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + normalized.length, length: 0))
    }

    /// Après un titre, la ligne suivante revient au texte normal.
    private func resetStyleAfterHeading(_ before: [NSAttributedString.Key: Any]) {
        let size = (before[.font] as? NSFont)?.pointSize ?? 0
        guard size >= Prefs.size * 1.2 else { return }
        var attrs = typingAttributes
        attrs[.font] = RichText.font(family: Prefs.family, size: Prefs.size)
        typingAttributes = attrs
    }

    override func insertNewline(_ sender: Any?) {
        let before = typingAttributes
        defer { resetStyleAfterHeading(before) }
        let sel = selectedRange()
        if sel.length == 0 {
            let (lineRange, line) = currentLine
            let lineLength = (line as NSString).length
            let offset = sel.location - lineRange.location
            let atEnd = offset == lineLength

            if atEnd, Separators.isTrigger(line) {
                replace(NSRange(location: lineRange.location, length: lineLength), Prefs.separatorText)
                super.insertNewline(sender)
                return
            }
            if Prefs.smart, ListTools.parse(line) != nil {
                switch ListTools.onReturn(line: String(line.prefix(offset)), glyph: Prefs.glyph) {
                case .insert(let s):
                    replace(sel, s)
                    return
                case .endList(let n) where atEnd:
                    replace(NSRange(location: lineRange.location, length: n), "")
                    return
                default: break
                }
            }
        }
        super.insertNewline(sender)
    }

    private func shiftLines(_ transform: (String) -> String) -> Bool {
        let ns = string as NSString
        let paragraphs = ns.paragraphRange(for: selectedRange())
        let original = ns.substring(with: paragraphs)
        guard original.split(separator: "\n", omittingEmptySubsequences: true).contains(where: { ListTools.parse(String($0)) != nil }) else { return false }
        let hadNewline = original.hasSuffix("\n")
        let shifted = original.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, line -> String in
            let s = String(line)
            return ListTools.parse(s) != nil ? transform(s) : s
        }.joined(separator: "\n")
        _ = hadNewline
        let selection = selectedRange()
        replace(paragraphs, shifted)
        setSelectedRange(NSRange(location: min(selection.location, (string as NSString).length), length: 0))
        return true
    }

    override func insertTab(_ sender: Any?) {
        if Prefs.smart, shiftLines(ListTools.indented) { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if Prefs.smart, shiftLines(ListTools.outdented) { return }
        super.insertBacktab(sender)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if Prefs.smart, let typed = insertString as? String, typed == " ", selectedRange().length == 0 {
            let (lineRange, _) = currentLine
            let before = (string as NSString).substring(with: NSRange(location: lineRange.location, length: selectedRange().location - lineRange.location))
            if let substitute = ListTools.bulletSubstitution(beforeCursor: before, glyph: Prefs.glyph) {
                replace(NSRange(location: lineRange.location, length: (before as NSString).length), substitute)
                return
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    /// Appelé quand la souris est relâchée : la sélection est alors stable, la mini-barre peut s'afficher.
    var onSelectionSettled: (() -> Void)?

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        onSelectionSettled?()
    }

    /// Un clic sur « [ ] » ou « [x] » coche ou décoche la tâche, sans déplacer le curseur.
    override func mouseDown(with event: NSEvent) {
        let ns = string as NSString
        if ns.length > 0 {
            let index = min(characterIndexForInsertion(at: convert(event.locationInWindow, from: nil)), ns.length)
            let lineRange = ns.lineRange(for: NSRange(location: min(index, ns.length - 1), length: 0))
            var line = ns.substring(with: lineRange)
            if line.hasSuffix("\n") { line.removeLast() }
            if let item = ListTools.parse(line), let box = item.checkboxRange, let toggled = ListTools.toggled(line) {
                let offset = index - lineRange.location
                if offset >= box.lowerBound, offset <= box.upperBound {
                    let boxRange = NSRange(location: lineRange.location + box.lowerBound, length: box.count)
                    let newBox = String(Array(toggled)[box])
                    guard shouldChangeText(in: boxRange, replacementString: newBox) else { return }
                    textStorage?.replaceCharacters(in: boxRange, with: newBox)
                    // Tâche faite : texte barré.
                    let content = NSRange(location: lineRange.location + item.markerLength, length: max(0, lineRange.length - item.markerLength - (ns.substring(with: lineRange).hasSuffix("\n") ? 1 : 0)))
                    if content.length > 0 {
                        if newBox == "☑" { textStorage?.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content) }
                        else { textStorage?.removeAttribute(.strikethroughStyle, range: content) }
                    }
                    didChangeText()
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
}

/// NSTextView dans un NSScrollView, relié à une note du magasin. Le texte est enrichi : la note est enregistrée en RTF.
struct NoteEditor: NSViewRepresentable {
    let noteID: UUID
    let text: String
    let rtf: Data?
    let fontSize: Double
    let fontFamily: String
    let onChange: (String, Data) -> Void
    let onSelection: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        let view = NoteTextView()
        view.isRichText = true
        view.importsGraphics = false
        view.usesFontPanel = false
        view.usesRuler = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticLinkDetectionEnabled = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 28, height: 24)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.insertionPointColor = NSColor(Socle.C.accentText)
        view.selectedTextAttributes = [.backgroundColor: NSColor(Socle.C.accent).withAlphaComponent(0.35)]
        view.linkTextAttributes = [.foregroundColor: NSColor(Socle.C.accentText), .underlineStyle: NSUnderlineStyle.single.rawValue,
                                   .cursor: NSCursor.pointingHand]
        view.delegate = context.coordinator
        scroll.documentView = view
        context.coordinator.textView = view
        EditorController.shared.textView = view
        context.coordinator.load(noteID: noteID, text: text, rtf: rtf)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.load(noteID: noteID, text: text, rtf: rtf)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        weak var textView: NoteTextView?
        private var loadedID: UUID?
        /// Contenu de la note tel que la zone de texte le connaît : tant qu'il ne change pas, on ne recharge pas.
        private var knownText = ""
        private var knownRTF: Data?
        private var appliedSize: CGFloat = RichText.reference
        private var appliedFamily = ""
        private var mini: NSHostingView<MiniToolbar>?

        init(_ parent: NoteEditor) { self.parent = parent }

        func load(noteID: UUID, text: String, rtf: Data?) {
            guard let view = textView, let storage = view.textStorage else { return }
            let family = parent.fontFamily
            let size = CGFloat(parent.fontSize)
            let switched = loadedID != noteID
            if switched || text != knownText || rtf != knownRTF {
                let selection = view.selectedRange()
                let source = rtf.map { RichText.attributed(rtf: $0) } ?? RichText.attributed(markdown: text)
                isLoading = true
                storage.setAttributedString(RichText.display(source, family: family, size: size))
                view.typingAttributes = RichText.defaults(family: family, size: size)
                isLoading = false
                appliedSize = size
                appliedFamily = family
                knownText = text
                knownRTF = rtf
                loadedID = noteID
                if switched {
                    view.setSelectedRange(NSRange(location: 0, length: 0))
                    view.undoManager?.removeAllActions()
                    view.scrollToBeginningOfDocument(nil)
                } else {
                    view.setSelectedRange(NSRange(location: min(selection.location, storage.length), length: 0))
                }
                if switched, storage.length == 0 { view.window?.makeFirstResponder(view) }
            } else if appliedSize != size || appliedFamily != family {
                isLoading = true
                RichText.restyle(storage, family: family, scale: size / appliedSize)
                var attrs = view.typingAttributes
                attrs[.font] = RichText.font(family: family, size: size)
                view.typingAttributes = attrs
                isLoading = false
                appliedSize = size
                appliedFamily = family
            }
        }

        private var isLoading = false

        func textDidChange(_ notification: Notification) {
            guard !isLoading, let view = textView, let storage = view.textStorage else { return }
            let ns = view.string as NSString
            RichText.fixLists(storage, in: ns.paragraphRange(for: NSRange(location: min(view.selectedRange().location, ns.length), length: 0)))
            let plain = view.string
            let data = RichText.rtf(from: storage, appliedSize: appliedSize)
            knownText = plain
            knownRTF = data
            parent.onChange(plain, data)
            refreshActive()
            hideMini()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = textView else { return }
            let range = view.selectedRange()
            refreshActive()
            view.onSelectionSettled = { [weak self] in self?.showMini() }
            if range.length == 0 { hideMini() } else if NSEvent.pressedMouseButtons == 0 { showMini() }
            parent.onSelection(range.length > 0 ? (view.string as NSString).substring(with: range) : "")
        }

        private func refreshActive() {
            if EditorController.shared.textView === textView { EditorController.shared.refresh() }
        }

        // MARK: Mini-barre près de la sélection

        private func hideMini() { mini?.removeFromSuperview(); mini = nil }

        private func showMini() {
            guard let view = textView, view.selectedRange().length > 0, let layoutManager = view.layoutManager,
                  let container = view.textContainer else { hideMini(); return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: view.selectedRange(), actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += view.textContainerOrigin.x
            rect.origin.y += view.textContainerOrigin.y
            if mini == nil {
                let host = NSHostingView(rootView: MiniToolbar(controller: EditorController.shared))
                view.addSubview(host)
                mini = host
            }
            guard let host = mini else { return }
            let size = host.fittingSize
            var x = rect.midX - size.width / 2
            x = max(8, min(x, view.bounds.width - size.width - 8))
            var y = rect.minY - size.height - 8
            if y < 4 { y = rect.maxY + 8 }   // pas de place au-dessus : sous la sélection
            host.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL { NSWorkspace.shared.open(url); return true }
            return false
        }
    }
}
