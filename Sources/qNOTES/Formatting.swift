import AppKit
import SwiftUI
import qNOTESCore

/// Mise en forme de la sélection (gras, titres, listes, liens…) : chaque action passe par `shouldChangeText` / `didChangeText`,
/// donc ⌘Z les annule et la note est enregistrée.
extension NoteTextView {
    private var baseSize: CGFloat { Prefs.size }

    func editAttributes(_ range: NSRange, _ change: (NSTextStorage, NSRange) -> Void) {
        guard let storage = textStorage, shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        change(storage, range)
        storage.endEditing()
        didChangeText()
    }

    func format(_ action: FormatAction) {
        switch action {
        case .bold: toggleTrait(.boldFontMask)
        case .italic: toggleTrait(.italicFontMask)
        case .underline: toggleLine(.underlineStyle)
        case .strike: toggleLine(.strikethroughStyle)
        case .title, .subtitle, .body: setStyle(action)
        case .alignLeft: alignLeft(nil)
        case .alignCenter: alignCenter(nil)
        case .alignRight: alignRight(nil)
        case .bullet: toggleList(.bullet)
        case .numbered: toggleList(.numbered)
        case .task: toggleList(.task)
        case .link: promptLink()
        case .separator: insertSeparator()
        }
    }

    private var currentFont: NSFont { (typingAttributes[.font] as? NSFont) ?? RichText.font(family: Prefs.family, size: baseSize) }

    // MARK: Caractères

    private func toggleTrait(_ trait: NSFontTraitMask) {
        let manager = NSFontManager.shared
        let selection = selectedRange()
        if selection.length == 0 {
            let font = currentFont
            typingAttributes[.font] = manager.traits(of: font).contains(trait) ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
            return
        }
        var all = true
        textStorage?.enumerateAttribute(.font, in: selection) { value, _, _ in
            if let font = value as? NSFont, !manager.traits(of: font).contains(trait) { all = false }
        }
        editAttributes(selection) { storage, range in
            storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                let font = (value as? NSFont) ?? currentFont
                storage.addAttribute(.font, value: all ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait), range: sub)
            }
        }
    }

    private func toggleLine(_ key: NSAttributedString.Key) {
        let selection = selectedRange()
        let single = NSUnderlineStyle.single.rawValue
        if selection.length == 0 {
            if typingAttributes[key] != nil { typingAttributes[key] = nil } else { typingAttributes[key] = single }
            return
        }
        var all = true
        textStorage?.enumerateAttribute(key, in: selection) { value, _, _ in if (value as? Int ?? 0) == 0 { all = false } }
        editAttributes(selection) { storage, range in
            if all { storage.removeAttribute(key, range: range) } else { storage.addAttribute(key, value: single, range: range) }
        }
    }

    func setColor(_ hex: String?) {
        let selection = selectedRange()
        let color: NSColor = hex.map { NSColor(Color(hex: $0)) } ?? RichText.defaultColor
        if selection.length == 0 { typingAttributes[.foregroundColor] = color; return }
        editAttributes(selection) { storage, range in storage.addAttribute(.foregroundColor, value: color, range: range) }
    }

    // MARK: Paragraphes

    /// Titre, sous-titre ou texte : taille et graisse des paragraphes touchés par la sélection.
    private func setStyle(_ style: FormatAction) {
        let ns = string as NSString
        let target = ns.paragraphRange(for: selectedRange())
        let current = activeFormats()
        let wanted: FormatAction = current.contains(style) && style != .body ? .body : style
        let scale: CGFloat = wanted == .title ? RichText.titleScale : wanted == .subtitle ? RichText.subtitleScale : 1
        let manager = NSFontManager.shared
        func restyled(_ font: NSFont) -> NSFont {
            RichText.font(family: Prefs.family, size: baseSize * scale, bold: wanted != .body, italic: manager.traits(of: font).contains(.italicFontMask))
        }
        if target.length > 0 {
            editAttributes(target) { storage, range in
                storage.enumerateAttribute(.font, in: range) { value, sub, _ in
                    storage.addAttribute(.font, value: restyled((value as? NSFont) ?? currentFont), range: sub)
                }
            }
        }
        typingAttributes[.font] = restyled(currentFont)
    }

    private func paragraphs(in range: NSRange) -> [(text: String, range: NSRange)] {
        let ns = string as NSString
        var out: [(String, NSRange)] = []
        ns.enumerateSubstrings(in: range, options: .byParagraphs) { text, sub, _, _ in out.append((text ?? "", sub)) }
        return out
    }

    private func toggleList(_ style: ListTools.Style) {
        let ns = string as NSString
        let selection = selectedRange()
        let target = ns.paragraphRange(for: selection)
        var lines = paragraphs(in: target)
        if lines.isEmpty { lines = [("", NSRange(location: selection.location, length: 0))] }
        let old = lines.map(\.text)
        let new = ListTools.toggle(style, lines: old, glyph: Prefs.glyph)
        guard new != old, let storage = textStorage, shouldChangeText(in: target, replacementString: nil) else { return }
        var delta = 0
        var caretShift = 0
        storage.beginEditing()
        for index in lines.indices.reversed() where new[index] != old[index] {
            let item = ListTools.parse(old[index])
            let indent = item?.indent ?? String(old[index].prefix(while: { $0 == " " || $0 == "\t" }))
            let content = item?.content ?? String(old[index].dropFirst(indent.count))
            let oldMarker = String(old[index].dropFirst(indent.count).prefix((item?.markerLength ?? indent.count) - indent.count))
            let newMarker = String(new[index].dropFirst(indent.count).dropLast(content.count))
            let at = lines[index].range.location + indent.utf16.count
            var attrs: [NSAttributedString.Key: Any] = lines[index].range.length > 0 && at < storage.length
                ? storage.attributes(at: min(at, storage.length - 1), effectiveRange: nil) : typingAttributes
            for key in [NSAttributedString.Key.underlineStyle, .strikethroughStyle, .link, .backgroundColor] { attrs[key] = nil }
            storage.replaceCharacters(in: NSRange(location: at, length: oldMarker.utf16.count),
                                      with: NSAttributedString(string: newMarker, attributes: attrs))
            delta += newMarker.utf16.count - oldMarker.utf16.count
            if selection.length == 0 { caretShift = newMarker.utf16.count - oldMarker.utf16.count }
        }
        RichText.fixLists(storage, in: NSRange(location: target.location, length: max(0, target.length + delta)))
        storage.endEditing()
        didChangeText()
        if selection.length == 0 { setSelectedRange(NSRange(location: max(0, selection.location + caretShift), length: 0)) }
        else { setSelectedRange(NSRange(location: target.location, length: max(0, target.length + delta - (string.hasSuffix("\n") ? 1 : 0)))) }
    }

    // MARK: Insertions

    private func promptLink() {
        let selection = selectedRange()
        guard selection.length > 0 else { NSSound.beep(); return }
        if textStorage?.attribute(.link, at: selection.location, effectiveRange: nil) != nil {
            editAttributes(selection) { storage, range in
                storage.removeAttribute(.link, range: range)
                storage.removeAttribute(.underlineStyle, range: range)
            }
            return
        }
        let alert = NSAlert()
        alert.messageText = L("fmt.link.title")
        alert.informativeText = L("fmt.link.message")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "https://…"
        if let pasted = NSPasteboard.general.string(forType: .string), pasted.hasPrefix("http") { field.stringValue = pasted }
        alert.accessoryView = field
        alert.addButton(withTitle: L("fmt.link.ok"))
        alert.addButton(withTitle: L("common.cancel"))
        alert.window.initialFirstResponder = field
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            var address = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !address.isEmpty else { return }
            if !address.contains(":") { address = "https://" + address }
            guard let url = URL(string: address) else { return }
            self.editAttributes(selection) { storage, range in
                storage.addAttributes([.link: url, .underlineStyle: NSUnderlineStyle.single.rawValue], range: range)
            }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: finish) } else { finish(alert.runModal()) }
    }

    private func insertSeparator() {
        let ns = string as NSString
        let paragraph = ns.paragraphRange(for: NSRange(location: min(selectedRange().location, ns.length), length: 0))
        let line = ns.substring(with: paragraph).trimmingCharacters(in: .newlines)
        let separator = Prefs.separatorText
        let range: NSRange
        let text: String
        if line.isEmpty {
            range = paragraph
            text = separator + "\n"
        } else {
            range = NSRange(location: paragraph.upperBound, length: 0)
            text = (ns.substring(with: paragraph).hasSuffix("\n") ? "" : "\n") + separator + "\n"
        }
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: RichText.defaults(family: Prefs.family, size: baseSize)))
        didChangeText()
        setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
    }

    // MARK: État

    /// Mises en forme sous le curseur ou la sélection (boutons allumés).
    func activeFormats() -> Set<FormatAction> {
        var active: Set<FormatAction> = []
        let ns = string as NSString
        let selection = selectedRange()
        let manager = NSFontManager.shared

        func everyRun(_ test: ([NSAttributedString.Key: Any]) -> Bool) -> Bool {
            if selection.length == 0 || ns.length == 0 { return test(typingAttributes) }
            var all = true
            textStorage?.enumerateAttributes(in: NSIntersectionRange(selection, NSRange(location: 0, length: ns.length))) { attrs, _, _ in
                if !test(attrs) { all = false }
            }
            return all
        }
        if everyRun({ ($0[.font] as? NSFont).map { manager.traits(of: $0).contains(.boldFontMask) } ?? false }) { active.insert(.bold) }
        if everyRun({ ($0[.font] as? NSFont).map { manager.traits(of: $0).contains(.italicFontMask) } ?? false }) { active.insert(.italic) }
        if everyRun({ (($0[.underlineStyle] as? Int) ?? 0) != 0 }) { active.insert(.underline) }
        if everyRun({ (($0[.strikethroughStyle] as? Int) ?? 0) != 0 }) { active.insert(.strike) }

        let probe: [NSAttributedString.Key: Any] = selection.length > 0 && selection.location < ns.length
            ? (textStorage?.attributes(at: selection.location, effectiveRange: nil) ?? typingAttributes) : typingAttributes
        let size = (probe[.font] as? NSFont)?.pointSize ?? baseSize
        active.insert(size >= baseSize * 1.45 ? .title : size >= baseSize * 1.2 ? .subtitle : .body)
        switch (probe[.paragraphStyle] as? NSParagraphStyle)?.alignment {
        case .center: active.insert(.alignCenter)
        case .right: active.insert(.alignRight)
        default: active.insert(.alignLeft)
        }
        let line = ns.length == 0 ? "" : ns.substring(with: ns.paragraphRange(for: NSRange(location: min(selection.location, ns.length), length: 0))).trimmingCharacters(in: .newlines)
        if let item = ListTools.parse(line) {
            switch item.kind {
            case .bullet: active.insert(.bullet)
            case .number: active.insert(.numbered)
            case .check: active.insert(.task)
            }
        }
        if ns.length > 0, selection.location < ns.length, textStorage?.attribute(.link, at: selection.location, effectiveRange: nil) != nil { active.insert(.link) }
        return active
    }
}
