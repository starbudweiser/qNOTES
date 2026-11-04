import AppKit
import SwiftUI
import qNOTESCore

/// Zone de texte : puces intelligentes, séparateurs personnalisés, cases à cocher cliquables.
final class NoteTextView: NSTextView {
    private func replace(_ range: NSRange, _ string: String) {
        if shouldChangeText(in: range, replacementString: string) {
            replaceCharacters(in: range, with: string)
            didChangeText()
        }
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
            } else if styledSize != parent.fontSize || styledSeparator != parent.separator {
                restyle(storage)
            }
            if switched, text.isEmpty { view.window?.makeFirstResponder(view) }
        }

        private var isLoading = false

        private func restyle(_ storage: NSTextStorage) {
            styledSize = parent.fontSize
            styledSeparator = parent.separator
            MarkdownStyler.apply(to: storage, fontSize: CGFloat(parent.fontSize), separator: parent.separator)
            textView?.typingAttributes = [.font: NSFont.systemFont(ofSize: CGFloat(parent.fontSize)), .foregroundColor: NSColor(Socle.C.text)]
        }

        func textDidChange(_ notification: Notification) {
            guard !isLoading, let view = textView, let storage = view.textStorage else { return }
            if !view.hasMarkedText() { restyle(storage) }
            parent.onChange(view.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = textView else { return }
            let range = view.selectedRange()
            parent.onSelection(range.length > 0 ? (view.string as NSString).substring(with: range) : "")
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL { NSWorkspace.shared.open(url); return true }
            return false
        }
    }
}
