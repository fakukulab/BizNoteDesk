import AppKit
import SwiftUI

struct NoteMemoEditor: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    @Binding var rtf: String
    var accessibilityTitle = String(localized: "note.freeMemo")
    var bulletOnly = false

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSStackView {
        let scrollView = NSTextView.scrollableTextView()
        let editor = scrollView.documentView as! NSTextView
        editor.delegate = context.coordinator
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsUndo = isEnabled
        editor.drawsBackground = false
        editor.textColor = .labelColor
        editor.textContainerInset = NSSize(width: 0, height: 4)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.lineFragmentPadding = 0
        editor.setAccessibilityLabel(accessibilityTitle)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let coordinator = context.coordinator
        coordinator.editor = editor
        coordinator.load()

        let toolbar = NSStackView(views: bulletOnly ? [] : [
            formatButton("bold", title: String(localized: "note.editor.bold", defaultValue: "굵게"),
                         action: #selector(Coordinator.bold), target: coordinator),
            formatButton("italic", title: String(localized: "note.editor.italic", defaultValue: "기울임꼴"),
                         action: #selector(Coordinator.italic), target: coordinator),
            formatButton("underline", title: String(localized: "note.editor.underline", defaultValue: "밑줄"),
                         action: #selector(Coordinator.underline), target: coordinator),
            formatButton("strikethrough", title: String(localized: "note.editor.strikethrough", defaultValue: "취소선"),
                         action: #selector(Coordinator.strikeThrough), target: coordinator),
            formatButton("textformat.size.larger", title: String(localized: "note.editor.heading", defaultValue: "제목"),
                         action: #selector(Coordinator.heading), target: coordinator),
            formatButton("textformat.size.smaller", title: String(localized: "note.editor.body", defaultValue: "본문"),
                         action: #selector(Coordinator.bodyText), target: coordinator),
            formatButton("list.bullet", title: String(localized: "note.editor.bulletedList", defaultValue: "글머리 기호 목록"),
                         action: #selector(Coordinator.bullets), target: coordinator),
            formatButton("list.number", title: String(localized: "note.editor.numberedList", defaultValue: "번호 목록"),
                         action: #selector(Coordinator.numbers), target: coordinator)
        ])
        editor.isEditable = isEnabled
        toolbar.isHidden = !isEnabled
        toolbar.spacing = 8

        let stack = NSStackView(views: bulletOnly ? [scrollView] : [toolbar, scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    func updateNSView(_ view: NSStackView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.editor?.isEditable = isEnabled
        coordinator.editor?.allowsUndo = isEnabled
        if !bulletOnly {
            view.arrangedSubviews.first?.isHidden = !isEnabled
        }
        coordinator.load()
    }

    private func formatButton(_ symbol: String, title: String, action: Selector, target: Coordinator) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.title = title
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.target = target
        button.action = action
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    static func displayText(_ text: String, rtf: String) -> NSAttributedString {
        let content = NSMutableAttributedString(
            string: text,
            attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]
        )
        if let data = Data(base64Encoded: rtf),
           let attributed = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                                   documentAttributes: nil),
           attributed.string == text {
            content.setAttributedString(attributed)
        }
        // Use the active appearance's text color for RTF from either platform.
        content.addAttribute(.foregroundColor, value: NSColor.labelColor,
                             range: NSRange(location: 0, length: content.length))
        return content
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteMemoEditor
        weak var editor: NSTextView?
        private var loadedText: String?
        private var loadedRTF: String?
        private var loadedIsEnabled: Bool?

        init(parent: NoteMemoEditor) {
            self.parent = parent
        }

        func load() {
            guard let editor,
                  loadedText != parent.text || loadedRTF != parent.rtf || loadedIsEnabled != parent.isEnabled else { return }
            loadedIsEnabled = parent.isEnabled
            loadedText = parent.text
            loadedRTF = parent.rtf

            if parent.bulletOnly {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 4
                style.paragraphSpacing = 4
                style.headIndent = 12
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: style
                ]
                let lines = parent.text.replacingOccurrences(of: "\r\n", with: "\n")
                    .components(separatedBy: .newlines)
                let display = !parent.isEnabled && parent.text.isEmpty
                    ? ""
                    : lines.map { "• " + $0 }.joined(separator: "\n")
                let selection = editor.selectedRange()
                editor.textStorage?.setAttributedString(NSAttributedString(string: display, attributes: attributes))
                editor.setSelectedRange(NSRange(location: min(max(2, selection.location), (display as NSString).length), length: 0))
                editor.typingAttributes = attributes
                return
            }

            editor.textStorage?.setAttributedString(NoteMemoEditor.displayText(parent.text, rtf: parent.rtf))
            editor.typingAttributes = [
                .font: NSFont.preferredFont(forTextStyle: .body),
                .foregroundColor: NSColor.labelColor
            ]
        }

        private var insertingBullet = false

        func textView(_ editor: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard parent.bulletOnly, !insertingBullet, let replacementString,
                  editor.undoManager?.isUndoing != true, editor.undoManager?.isRedoing != true else { return true }
            let lines = replacementString
                .replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: .newlines)
            let text = editor.string as NSString
            let start = text.lineRange(for: NSRange(location: range.location, length: 0)).location
            let protectedEnd = text.substring(from: start).hasPrefix("• ") ? start + 2 : start
            var editRange = NSRange(location: max(range.location, protectedEnd), length: 0)
            editRange.length = max(0, NSMaxRange(range) - editRange.location)

            if replacementString.isEmpty, range.length == 1, start > 0,
               range.location == start + 1, editor.selectedRange().location == protectedEnd {
                // Backspace at the start of an item joins it to the previous item.
                editRange = NSRange(location: start - 1, length: 3)
            } else if range.length > 0, NSMaxRange(range) < text.length,
                      text.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1)) == "\n",
                      text.substring(from: NSMaxRange(range)).hasPrefix("• ") {
                editRange.length += 2
            }

            let replacement = lines.joined(separator: "\n• ")
            guard editRange != range || replacement != replacementString else { return true }
            guard editRange.length > 0 || !replacement.isEmpty else { return false }
            insertingBullet = true
            editor.insertText(replacement, replacementRange: editRange)
            insertingBullet = false
            return false
        }

        func textDidChange(_ notification: Notification) {
            persist()
        }

        @objc func bold() { toggleFontTrait(.boldFontMask) }
        @objc func italic() { toggleFontTrait(.italicFontMask) }

        @objc func strikeThrough() {
            guard let editor else { return }
            let selection = editor.selectedRange()
            let value = selection.length == 0
                ? editor.typingAttributes[.strikethroughStyle]
                : editor.textStorage?.attribute(.strikethroughStyle, at: selection.location, effectiveRange: nil)
            let enabled = (value as? Int ?? 0) != 0
            applyAttribute(.strikethroughStyle, value: enabled ? 0 : NSUnderlineStyle.single.rawValue)
        }

        @objc func heading() {
            applyAttribute(.font, value: NSFont.systemFont(ofSize: 17, weight: .semibold))
        }

        @objc func bodyText() {
            applyAttribute(.font, value: NSFont.preferredFont(forTextStyle: .body))
        }

        @objc func bullets() { applyList(numbered: false) }
        @objc func numbers() { applyList(numbered: true) }

        private func applyAttribute(_ key: NSAttributedString.Key, value: Any) {
            guard let editor else { return }
            editor.window?.makeFirstResponder(editor)
            let selection = editor.selectedRange()
            if selection.length == 0 {
                editor.typingAttributes[key] = value
                return
            }
            guard editor.shouldChangeText(in: selection, replacementString: nil) else { return }
            editor.textStorage?.addAttribute(key, value: value, range: selection)
            editor.didChangeText()
        }

        private static let bulletPattern = #"^•[ \t]+"#
        private static let numberPattern = #"^[0-9]+\.[ \t]+"#

        func textView(_ editor: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !parent.bulletOnly, commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let selection = editor.selectedRange()
            guard selection.length == 0 else { return false }

            let text = editor.string as NSString
            let paragraph = text.paragraphRange(for: selection)
            let line = text.substring(with: paragraph)
            let markerPattern = Self.bulletPattern + "|" + Self.numberPattern
            guard let marker = line.range(of: markerPattern, options: .regularExpression) else { return false }
            let markerLength = NSRange(marker, in: line).length
            guard selection.location >= paragraph.location + markerLength else { return false }

            let prefix = line[marker]
            let item = line[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if item.isEmpty {
                editor.insertText("", replacementRange: NSRange(location: paragraph.location, length: markerLength))
            } else if prefix.hasPrefix("•") {
                editor.insertText("\n• ", replacementRange: selection)
            } else if let number = Int(prefix.prefix(while: { $0.isASCII && $0.isNumber })), number < Int.max {
                editor.insertText("\n\(number + 1). ", replacementRange: selection)
            } else {
                return false
            }
            return true
        }

        private func applyList(numbered: Bool) {
            guard let editor, let storage = editor.textStorage else { return }
            editor.window?.makeFirstResponder(editor)
            let selection = editor.selectedRange()
            let paragraphRange = (storage.string as NSString).paragraphRange(for: selection)
            let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: paragraphRange))
            let content = replacement.string as NSString
            var lines: [NSRange] = []
            if content.length > 0 {
                content.enumerateSubstrings(in: NSRange(location: 0, length: content.length), options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
                    lines.append(range)
                }
            }
            if lines.isEmpty {
                lines = [NSRange(location: 0, length: 0)]
            }

            let markerPattern = Self.bulletPattern + "|" + Self.numberPattern
            let sameStyle = numbered ? Self.numberPattern : Self.bulletPattern
            let remove = lines.allSatisfy {
                content.substring(with: $0).range(of: sameStyle, options: .regularExpression) != nil
            }

            for (index, line) in lines.enumerated().reversed() {
                let lineText = content.substring(with: line)
                let attributes = line.length > 0
                    ? replacement.attributes(at: line.location, effectiveRange: nil)
                    : editor.typingAttributes
                let marker = lineText.range(of: markerPattern, options: .regularExpression)
                let oldLength = marker.map { NSRange($0, in: lineText).length } ?? 0
                let prefix = remove ? "" : (numbered ? "\(index + 1). " : "• ")
                replacement.replaceCharacters(in: NSRange(location: line.location, length: oldLength),
                                              with: NSAttributedString(string: prefix, attributes: attributes))
            }

            guard editor.shouldChangeText(in: paragraphRange, replacementString: replacement.string) else { return }
            storage.replaceCharacters(in: paragraphRange, with: replacement)
            let newSelection: NSRange
            if selection.length == 0 {
                let delta = replacement.length - paragraphRange.length
                newSelection = NSRange(location: max(paragraphRange.location, selection.location + delta), length: 0)
            } else {
                newSelection = NSRange(location: paragraphRange.location, length: replacement.length)
            }
            editor.setSelectedRange(newSelection)
            editor.didChangeText()
        }

        @objc func underline() {
            guard let editor else { return }
            editor.window?.makeFirstResponder(editor)
            editor.underline(nil)
            persist()
        }

        private func toggleFontTrait(_ trait: NSFontTraitMask) {
            guard let editor, let storage = editor.textStorage else { return }
            editor.window?.makeFirstResponder(editor)
            let selection = editor.selectedRange()
            let manager = NSFontManager.shared
            let bodyFont = NSFont.preferredFont(forTextStyle: .body)
            if selection.length == 0 {
                var attributes = editor.typingAttributes
                let font = attributes[.font] as? NSFont ?? bodyFont
                attributes[.font] = manager.traits(of: font).contains(trait)
                    ? manager.convert(font, toNotHaveTrait: trait)
                    : manager.convert(font, toHaveTrait: trait)
                editor.typingAttributes = attributes
                return
            }

            guard editor.shouldChangeText(in: selection, replacementString: nil) else { return }
            let firstFont = storage.attribute(.font, at: selection.location, effectiveRange: nil) as? NSFont ?? bodyFont
            let remove = manager.traits(of: firstFont).contains(trait)
            // Enumerate a snapshot because the font runs in the text storage change as we apply formatting.
            let selectionContents = storage.attributedSubstring(from: selection)
            storage.beginEditing()
            selectionContents.enumerateAttribute(.font, in: NSRange(location: 0, length: selection.length)) { value, range, _ in
                let font = value as? NSFont ?? bodyFont
                let updated = remove ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
                storage.addAttribute(.font, value: updated, range: NSRange(location: selection.location + range.location, length: range.length))
            }
            storage.endEditing()
            editor.didChangeText()
        }

        private func persist() {
            guard let editor, editor.isEditable, let storage = editor.textStorage else { return }
            if parent.bulletOnly {
                let text = storage.string.components(separatedBy: "\n")
                    .map { $0.hasPrefix("• ") ? String($0.dropFirst(2)) : $0 }
                    .joined(separator: "\n")
                loadedText = text
                if parent.text != text { parent.text = text }
                return
            }
            let text = storage.string
            let range = NSRange(location: 0, length: storage.length)
            let rtf = storage.rtf(from: range, documentAttributes: [:])?.base64EncodedString() ?? ""
            loadedText = text
            loadedRTF = rtf
            if parent.text != text { parent.text = text }
            if parent.rtf != rtf { parent.rtf = rtf }
        }
    }
}
