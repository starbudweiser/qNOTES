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

    /// Applique une modification de l'assistant Markdown (annulable avec ⌘Z) puis place la sélection.
    func apply(_ edit: TextEdit) {
        replace(edit.range, edit.replacement)
        setSelectedRange(NSRange(location: min(edit.selection.location, (string as NSString).length),
                                 length: min(edit.selection.length, max(0, (string as NSString).length - edit.selection.location))))
        scrollRangeToVisible(selectedRange())
    }

    private var currentLine: (range: NSRange, text: String) {
        let ns = string as NSString
        let range = ns.lineRange(for: NSRange(location: min(selectedRange().location, ns.length), length: 0))
        var text = ns.substring(with: range)
        if text.hasSuffix("\n") { text.removeLast() }
        return (range, text)
    }

    override func insertNewline(_ sender: Any?) {
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
                    let position = lineRange.location + box.lowerBound + 1
                    replace(NSRange(location: position, length: 1), String(Array(toggled)[box.lowerBound + 1]))
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
}

/// NSTextView dans un NSScrollView, relié à une note du magasin.
struct NoteEditor: NSViewRepresentable {
    let noteID: UUID
    let text: String
    let fontSize: Double
    let separator: String
    let layout: Bool
    let onChange: (String) -> Void
    let onSelection: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true

        let view = NoteTextView()
        view.isRichText = false          // le texte reste du Markdown brut ; la mise en forme est un affichage
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
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
        context.coordinator.load(noteID: noteID, text: text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.load(noteID: noteID, text: text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        weak var textView: NoteTextView?
        private var loadedID: UUID?
        private var styledSize: Double = 0
        private var styledSeparator = ""
        private var styledLayout = true
        private var lastActive = NSRange(location: NSNotFound, length: 0)
        private var mini: NSHostingView<MiniToolbar>?

        init(_ parent: NoteEditor) { self.parent = parent }

        func load(noteID: UUID, text: String) {
            guard let view = textView, let storage = view.textStorage else { return }
            let switched = loadedID != noteID
            if switched || view.string != text {
                let selection = view.selectedRange()
                isLoading = true
                view.string = text
                isLoading = false
                if switched {
                    view.setSelectedRange(NSRange(location: 0, length: 0))
                    view.undoManager?.removeAllActions()
                    view.scrollToBeginningOfDocument(nil)
                } else {
                    view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
                }
                loadedID = noteID
                restyle(storage)
            } else if styledSize != parent.fontSize || styledSeparator != parent.separator || styledLayout != parent.layout {
                restyle(storage)
            }
            if switched, text.isEmpty { view.window?.makeFirstResponder(view) }
        }

        private var isLoading = false

        private func restyle(_ storage: NSTextStorage) {
            styledSize = parent.fontSize
            styledSeparator = parent.separator
            styledLayout = parent.layout
            let active = textView?.selectedRange() ?? NSRange(location: 0, length: 0)
            lastActive = (storage.string as NSString).paragraphRange(for: active)
            MarkdownStyler.apply(to: storage, fontSize: CGFloat(parent.fontSize), separator: parent.separator,
                                 hideMarkers: parent.layout, active: active)
            textView?.typingAttributes = [.font: NSFont.systemFont(ofSize: CGFloat(parent.fontSize)), .foregroundColor: NSColor(Socle.C.text)]
        }

        func textDidChange(_ notification: Notification) {
            guard !isLoading, let view = textView, let storage = view.textStorage else { return }
            if !view.hasMarkedText() { restyle(storage) }
            parent.onChange(view.string)
            refreshActive()
            hideMini()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = textView else { return }
            let range = view.selectedRange()
            // Mise en page : la ligne active change, donc les balises affichées aussi.
            if parent.layout, !view.hasMarkedText(), let storage = view.textStorage {
                let para = (view.string as NSString).paragraphRange(for: range)
                if para != lastActive || range.length > 0 { restyle(storage) }
            }
            refreshActive()
            view.onSelectionSettled = { [weak self] in self?.showMini() }
            if range.length == 0 { hideMini() } else if NSEvent.pressedMouseButtons == 0 { showMini() }
            parent.onSelection(range.length > 0 ? (view.string as NSString).substring(with: range) : "")
        }

        private func refreshActive() {
            guard let view = textView else { return }
            EditorController.shared.active = MarkdownAssistant.activeActions(in: view.string, selection: view.selectedRange())
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
