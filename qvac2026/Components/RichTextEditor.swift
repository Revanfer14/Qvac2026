//
//  RichTextEditor.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 15/06/26.
//

import UIKit
import SwiftUI
import Combine

// MARK: - RichTextController

final class RichTextController: ObservableObject {
    @Published var attributedText: NSAttributedString = NSAttributedString()
    @Published var isEmpty: Bool = true
    @Published var isFocused: Bool = false

    weak var textView: UITextView?

    private let defaultFont = UIFont(name: "HelveticaNeue", size: 15) ?? .systemFont(ofSize: 15)

    /// Default attributes for body text. Always includes the dynamic label color so
    /// text is readable in both light and dark mode.
    private var bodyAttrs: [NSAttributedString.Key: Any] {
        [.font: defaultFont, .foregroundColor: UIColor.label]
    }

    func loadInitialContent(note: Note?) {
        if let data = note?.contentRTF {
            // 1. Try our custom NSKeyedArchiver format (notes with inline audio).
            if let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) {
                unarchiver.requiresSecureCoding = false
                let decoded = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? NSAttributedString
                unarchiver.finishDecoding()
                if let attrStr = decoded {
                    attributedText = attrStr
                    isEmpty = attrStr.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    return
                }
            }
            // 2. Fall back to RTF (older notes).
            if let attrStr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) {
                attributedText = attrStr
                isEmpty = attrStr.string.isEmpty
                return
            }
        }
        // 3. Fall back to plain text.
        if let plain = note?.content, !plain.isEmpty {
            attributedText = NSAttributedString(string: plain, attributes: bodyAttrs)
            isEmpty = false
            return
        }
        attributedText = NSAttributedString()
        isEmpty = true
    }

    // MARK: Bold / Italic

    func toggleBold() {
        toggleTrait(.traitBold)
    }

    func toggleItalic() {
        toggleTrait(.traitItalic)
    }

    private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        guard range.length > 0 else {
            // toggle typingAttributes for next character
            let current = tv.typingAttributes[.font] as? UIFont ?? defaultFont
            tv.typingAttributes[.font] = current.toggling(trait)
            return
        }
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        mutable.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            let font = (value as? UIFont) ?? defaultFont
            mutable.addAttribute(.font, value: font.toggling(trait), range: subRange)
        }
        tv.attributedText = mutable
        tv.selectedRange = range
        sync(from: tv)
    }

    // MARK: Underline / Strikethrough

    func toggleUnderline() {
        toggleIntAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue)
    }

    func toggleStrikethrough() {
        toggleIntAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue)
    }

    private func toggleIntAttribute(_ key: NSAttributedString.Key, value: Int) {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        guard range.length > 0 else {
            let current = tv.typingAttributes[key] as? Int ?? 0
            tv.typingAttributes[key] = current == 0 ? value : 0
            return
        }
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        var isOn = false
        mutable.enumerateAttribute(key, in: range, options: []) { val, _, _ in
            if (val as? Int ?? 0) != 0 { isOn = true }
        }
        mutable.enumerateAttribute(key, in: range, options: []) { _, subRange, _ in
            mutable.addAttribute(key, value: isOn ? 0 : value, range: subRange)
        }
        tv.attributedText = mutable
        tv.selectedRange = range
        sync(from: tv)
    }

    // MARK: Headings

    func applyHeading(_ level: Int) {
        guard let tv = textView else { return }
        let (font, _) = headingFont(level)
        applyFontToParagraph(font, in: tv)
    }

    func applyBody() {
        guard let tv = textView else { return }
        applyFontToParagraph(defaultFont, in: tv)
    }

    private func headingFont(_ level: Int) -> (UIFont, CGFloat) {
        switch level {
        case 1:  return (UIFont(name: "HelveticaNeue-Bold", size: 28) ?? .boldSystemFont(ofSize: 28), 28)
        case 2:  return (UIFont(name: "HelveticaNeue-Bold", size: 22) ?? .boldSystemFont(ofSize: 22), 22)
        default: return (UIFont(name: "HelveticaNeue-Medium", size: 18) ?? .systemFont(ofSize: 18, weight: .semibold), 18)
        }
    }

    private func applyFontToParagraph(_ font: UIFont, in tv: UITextView) {
        let fullText = tv.attributedText.string as NSString
        let cursorPos = tv.selectedRange.location
        let paragraphRange = fullText.paragraphRange(for: NSRange(location: cursorPos, length: 0))
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        mutable.addAttribute(.font, value: font, range: paragraphRange)
        let savedRange = tv.selectedRange
        tv.attributedText = mutable
        tv.selectedRange = savedRange
        sync(from: tv)
    }

    // MARK: Lists

    func toggleBulletList() {
        insertParagraphPrefix("• ")
    }

    func toggleNumberedList() {
        insertParagraphPrefix("1. ")
    }

    func toggleChecklist() {
        insertParagraphPrefix("☐ ")
    }

    // MARK: List auto-continue helpers

    private enum ListKind { case bullet, checklist, numbered(Int) }

    /// Detects whether `content` (a paragraph string, trailing newline already stripped)
    /// begins with a known list marker. Returns the kind and the exact marker string.
    private func listContext(_ content: String) -> (kind: ListKind, marker: String)? {
        if content.hasPrefix("• ")  { return (.bullet,    "• ") }
        if content.hasPrefix("☐ ") { return (.checklist, "☐ ") }
        if content.hasPrefix("☑ ") { return (.checklist, "☑ ") }   // checked → continue unchecked
        let digits = content.prefix { $0.isNumber }
        if !digits.isEmpty, content.dropFirst(digits.count).hasPrefix(". ") {
            return (.numbered(Int(digits) ?? 1), "\(digits). ")
        }
        return nil
    }

    /// Called by the coordinator when the user presses Return.
    /// Returns `true` if it consumed the event (auto-continued or exited a list).
    func handleNewline(at range: NSRange) -> Bool {
        guard let tv = textView else { return false }
        let full = tv.text as NSString
        let paraRange = full.paragraphRange(for: NSRange(location: range.location, length: 0))
        var content = full.substring(with: paraRange)
        if content.hasSuffix("\n") { content.removeLast() }
        guard let ctx = listContext(content) else { return false }

        let body = String(content.dropFirst(ctx.marker.count))
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)

        if body.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty list item → exit list: strip the marker, don't insert a newline.
            let removeRange = NSRange(location: paraRange.location, length: ctx.marker.utf16.count)
            mutable.deleteCharacters(in: removeRange)
            tv.attributedText = mutable
            tv.selectedRange = NSRange(location: paraRange.location, length: 0)
        } else {
            // Non-empty item → continue list with the next marker (numbered auto-increments).
            let next: String
            switch ctx.kind {
            case .bullet:          next = "• "
            case .checklist:       next = "☐ "
            case .numbered(let n): next = "\(n + 1). "
            }
            let insertion = "\n" + next
            mutable.insert(
                NSAttributedString(string: insertion, attributes: bodyAttrs),
                at: range.location
            )
            tv.attributedText = mutable
            tv.selectedRange = NSRange(location: range.location + insertion.utf16.count, length: 0)
        }
        sync(from: tv)
        return true
    }

    private func insertParagraphPrefix(_ prefix: String) {
        guard let tv = textView else { return }
        let fullText = tv.text as NSString
        let cursorPos = tv.selectedRange.location
        let paraRange = fullText.paragraphRange(for: NSRange(location: cursorPos, length: 0))
        let paraText = fullText.substring(with: paraRange)

        if paraText.hasPrefix(prefix) {
            // already has prefix → remove it
            let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
            let removedRange = NSRange(location: paraRange.location, length: prefix.utf16.count)
            mutable.deleteCharacters(in: removedRange)
            tv.attributedText = mutable
            tv.selectedRange = NSRange(location: max(0, cursorPos - prefix.utf16.count), length: 0)
        } else {
            let insertion = NSAttributedString(string: prefix, attributes: bodyAttrs)
            let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
            mutable.insert(insertion, at: paraRange.location)
            tv.attributedText = mutable
            tv.selectedRange = NSRange(location: cursorPos + prefix.utf16.count, length: 0)
        }
        sync(from: tv)
    }

    // MARK: Indent

    func indentIncrease() { adjustIndent(by: 20) }
    func indentDecrease() { adjustIndent(by: -20) }

    private func adjustIndent(by delta: CGFloat) {
        guard let tv = textView else { return }
        let fullText = tv.attributedText.string as NSString
        let cursorPos = tv.selectedRange.location
        let paraRange = fullText.paragraphRange(for: NSRange(location: cursorPos, length: 0))

        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        mutable.enumerateAttribute(.paragraphStyle, in: paraRange, options: []) { val, subRange, _ in
            let existing = (val as? NSParagraphStyle) ?? NSParagraphStyle.default
            let style = existing.mutableCopy() as! NSMutableParagraphStyle
            style.headIndent = max(0, style.headIndent + delta)
            style.firstLineHeadIndent = max(0, style.firstLineHeadIndent + delta)
            mutable.addAttribute(.paragraphStyle, value: style, range: subRange)
        }
        let savedRange = tv.selectedRange
        tv.attributedText = mutable
        tv.selectedRange = savedRange
        sync(from: tv)
    }

    // MARK: Table

    /// Inserts an inline editable table at the current cursor position.
    /// A leading newline is added if the cursor isn't already at the start of a line;
    /// a trailing newline is always appended so typing continues below the table.
    func insertTable(host: TableAttachmentHosting) {
        guard let tv = textView else { return }

        let att = TableTextAttachment()
        att.host = host

        let insertion = NSMutableAttributedString()

        let insertionPoint = tv.selectedRange.location
        let fullNSStr = tv.attributedText.string as NSString
        let needsLeadingNewline = insertionPoint > 0
            && fullNSStr.character(at: insertionPoint - 1) != 10  // 10 = '\n'
        if needsLeadingNewline {
            insertion.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        }
        insertion.append(NSAttributedString(attachment: att))
        insertion.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        // Ensure the attachment glyph (U+FFFC) also carries the label color so
        // UITextView doesn't derive black typingAttributes from it later.
        insertion.addAttribute(.foregroundColor, value: UIColor.label,
                               range: NSRange(location: 0, length: insertion.length))

        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        mutable.insert(insertion, at: insertionPoint)
        tv.attributedText = mutable
        tv.selectedRange = NSRange(location: insertionPoint + insertion.length, length: 0)
        sync(from: tv)
    }

    /// Forces TextKit 2 to re-query all attachment bounds and rebuild attachment views.
    /// Used after rows/columns are added or removed from a TableTextAttachment.
    func refreshLayout() {
        guard let tv = textView else { return }
        let saved = tv.selectedRange
        // Reassigning attributed text causes TextKit 2 to call viewProvider(for:) and
        // attachmentBounds(for:) again for every attachment, rebuilding the grid UI.
        tv.attributedText = NSAttributedString(attributedString: tv.attributedText)
        tv.selectedRange = saved
        sync(from: tv)
    }

    // MARK: Inline audio

    /// Inserts an audio attachment card at the current cursor position.
    /// A newline is prepended if the cursor is not already at the start of a line,
    /// and a trailing newline is always appended so typing continues below the card.
    func insertAudio(_ attachment: Attachment, host: AudioAttachmentHosting) {
        guard let tv = textView else { return }

        let att = AudioTextAttachment(audioId: attachment.id.uuidString)
        att.host = host

        let insertion = NSMutableAttributedString()

        let insertionPoint = tv.selectedRange.location
        let fullNSStr = tv.attributedText.string as NSString
        let needsLeadingNewline = insertionPoint > 0
            && fullNSStr.character(at: insertionPoint - 1) != 10  // 10 = '\n'
        if needsLeadingNewline {
            insertion.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        }
        insertion.append(NSAttributedString(attachment: att))
        insertion.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        insertion.addAttribute(.foregroundColor, value: UIColor.label,
                               range: NSRange(location: 0, length: insertion.length))

        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        mutable.insert(insertion, at: insertionPoint)
        tv.attributedText = mutable
        // Place cursor on the empty line below the card
        tv.selectedRange = NSRange(location: insertionPoint + insertion.length, length: 0)
        sync(from: tv)
    }

    /// Removes the inline audio attachment with the given `audioId` from the text view,
    /// also consuming its trailing newline.
    func removeAudioAttachment(audioId: String) {
        guard let tv = textView else { return }
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        let fullNSStr = mutable.string as NSString
        var rangeToDelete: NSRange?

        mutable.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: mutable.length),
            options: .reverse
        ) { value, range, stop in
            if (value as? AudioTextAttachment)?.audioId == audioId {
                rangeToDelete = range
                stop.pointee = true
            }
        }

        guard var range = rangeToDelete else { return }
        // Consume the trailing newline so the card doesn't leave a blank line
        let afterEnd = range.location + range.length
        if afterEnd < fullNSStr.length && fullNSStr.character(at: afterEnd) == 10 {
            range.length += 1
        }

        mutable.deleteCharacters(in: range)
        tv.attributedText = mutable
        ensureTrailingTextSlot()
        sync(from: tv)
    }

    // MARK: Inline image

    /// Inserts an image attachment at the current cursor position.
    /// A newline is prepended if the cursor is not already at the start of a line,
    /// and a trailing newline is always appended so typing continues below the image.
    func insertImage(_ attachment: Attachment, host: ImageAttachmentHosting) {
        guard let tv = textView else { return }

        let att = ImageTextAttachment(imageId: attachment.id.uuidString)
        att.host = host

        let insertion = NSMutableAttributedString()

        let insertionPoint = tv.selectedRange.location
        let fullNSStr = tv.attributedText.string as NSString
        let needsLeadingNewline = insertionPoint > 0
            && fullNSStr.character(at: insertionPoint - 1) != 10  // 10 = '\n'
        if needsLeadingNewline {
            insertion.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        }
        insertion.append(NSAttributedString(attachment: att))
        insertion.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        insertion.addAttribute(.foregroundColor, value: UIColor.label,
                               range: NSRange(location: 0, length: insertion.length))

        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        mutable.insert(insertion, at: insertionPoint)
        tv.attributedText = mutable
        tv.selectedRange = NSRange(location: insertionPoint + insertion.length, length: 0)
        sync(from: tv)
    }

    /// Removes the inline image attachment with the given `imageId` from the text view,
    /// also consuming its trailing newline.
    func removeImageAttachment(imageId: String) {
        guard let tv = textView else { return }
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        let fullNSStr = mutable.string as NSString
        var rangeToDelete: NSRange?

        mutable.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: mutable.length),
            options: .reverse
        ) { value, range, stop in
            if (value as? ImageTextAttachment)?.imageId == imageId {
                rangeToDelete = range
                stop.pointee = true
            }
        }

        guard var range = rangeToDelete else { return }
        let afterEnd = range.location + range.length
        if afterEnd < fullNSStr.length && fullNSStr.character(at: afterEnd) == 10 {
            range.length += 1
        }

        mutable.deleteCharacters(in: range)
        tv.attributedText = mutable
        ensureTrailingTextSlot()
        sync(from: tv)
    }

    // MARK: Inline file

    /// Inserts a file attachment card at the current cursor position.
    /// A newline is prepended if the cursor is not already at the start of a line,
    /// and a trailing newline is always appended so typing continues below the card.
    func insertFile(_ attachment: Attachment, host: FileAttachmentHosting) {
        guard let tv = textView else { return }

        let att = FileTextAttachment(fileId: attachment.id.uuidString)
        att.host = host

        let insertion = NSMutableAttributedString()

        let insertionPoint = tv.selectedRange.location
        let fullNSStr = tv.attributedText.string as NSString
        let needsLeadingNewline = insertionPoint > 0
            && fullNSStr.character(at: insertionPoint - 1) != 10  // 10 = '\n'
        if needsLeadingNewline {
            insertion.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        }
        insertion.append(NSAttributedString(attachment: att))
        insertion.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        insertion.addAttribute(.foregroundColor, value: UIColor.label,
                               range: NSRange(location: 0, length: insertion.length))

        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        mutable.insert(insertion, at: insertionPoint)
        tv.attributedText = mutable
        tv.selectedRange = NSRange(location: insertionPoint + insertion.length, length: 0)
        sync(from: tv)
    }

    /// Removes the inline file attachment with the given `fileId` from the text view,
    /// also consuming its trailing newline.
    func removeFileAttachment(fileId: String) {
        guard let tv = textView else { return }
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        let fullNSStr = mutable.string as NSString
        var rangeToDelete: NSRange?

        mutable.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: mutable.length),
            options: .reverse
        ) { value, range, stop in
            if (value as? FileTextAttachment)?.fileId == fileId {
                rangeToDelete = range
                stop.pointee = true
            }
        }

        guard var range = rangeToDelete else { return }
        let afterEnd = range.location + range.length
        if afterEnd < fullNSStr.length && fullNSStr.character(at: afterEnd) == 10 {
            range.length += 1
        }

        mutable.deleteCharacters(in: range)
        tv.attributedText = mutable
        ensureTrailingTextSlot()
        sync(from: tv)
    }

    // MARK: Undo / Redo

    func undo() {
        guard let tv = textView, let mgr = tv.undoManager else { return }
        if mgr.canUndo { mgr.undo() }
        sync(from: tv)
    }

    func redo() {
        guard let tv = textView, let mgr = tv.undoManager else { return }
        if mgr.canRedo { mgr.redo() }
        sync(from: tv)
    }

    // MARK: Internal sync

    func sync(from tv: UITextView) {
        attributedText = tv.attributedText
        isEmpty = tv.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// TextKit 2 renders runs that have no explicit foreground color as black,
    /// ignoring UITextView.textColor. This stamps every character in the text
    /// storage with UIColor.label so older notes (saved without a color attribute)
    /// are readable in dark mode. Safe to call repeatedly — it only adds a color
    /// attribute; fonts, paragraph styles, and attachments are preserved.
    func normalizeForegroundColor(_ tv: UITextView) {
        let full = NSRange(location: 0, length: tv.textStorage.length)
        guard full.length > 0 else { return }
        tv.textStorage.beginEditing()
        tv.textStorage.addAttribute(.foregroundColor, value: UIColor.label, range: full)
        tv.textStorage.endEditing()
    }

    // MARK: - Caret placement helpers

    /// Guarantees the document never ends on a non-text attachment glyph (U+FFFC).
    /// Appends a trailing "\n" when the last character is an attachment so the user
    /// always has a typeable slot below the last block. Idempotent — a document
    /// already ending in a newline (the normal post-insert state) is left untouched.
    func ensureTrailingTextSlot() {
        guard let tv = textView else { return }
        let str = tv.attributedText.string as NSString
        guard str.length > 0,
              str.character(at: str.length - 1) == 0xFFFC else { return }
        let saved = tv.selectedRange
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        mutable.append(NSAttributedString(string: "\n", attributes: bodyAttrs))
        tv.attributedText = mutable
        tv.selectedRange = NSRange(location: min(saved.location, mutable.length), length: 0)
        sync(from: tv)
    }

    /// Places the caret at the very end of the document, appending a trailing
    /// text slot first when necessary, then makes the text view first responder.
    func focusAtEnd() {
        guard let tv = textView else { return }
        ensureTrailingTextSlot()
        tv.becomeFirstResponder()
        tv.selectedRange = NSRange(location: tv.attributedText.length, length: 0)
    }

    /// Moves the caret to the text position nearest to `point` (in text-view
    /// coordinates). Falls back to `focusAtEnd()` when `point` is below the
    /// last line of content.
    func placeCaret(at point: CGPoint) {
        guard let tv = textView else { return }
        let lastCaret = tv.caretRect(for: tv.endOfDocument)
        if point.y > lastCaret.maxY + 4 {
            focusAtEnd()
            return
        }
        guard let position = tv.closestPosition(to: point) else {
            focusAtEnd()
            return
        }
        tv.becomeFirstResponder()
        let offset = tv.offset(from: tv.beginningOfDocument, to: position)
        tv.selectedRange = NSRange(location: offset, length: 0)
    }

    // MARK: - Find-on-page

    private let searchHighlightColor       = UIColor.systemYellow.withAlphaComponent(0.50)
    private let searchActiveHighlightColor = UIColor.systemOrange.withAlphaComponent(0.65)

    /// All ranges matching the current search query, in document order.
    private var searchRanges: [NSRange] = []
    /// Index into searchRanges for the currently active (orange) match.
    private var currentSearchIndex: Int = 0

    /// Finds all case-insensitive occurrences of `query` in the note, highlights them
    /// via TextKit 2 rendering attributes (yellow for all, orange for the first), and
    /// scrolls the first match into view. Returns the total number of matches.
    @discardableResult
    func performSearch(_ query: String) -> Int {
        clearSearchHighlights()
        guard let tv = textView else { return 0 }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        // Match-finding reads textStorage.string — fine under TextKit 2.
        let fullString = tv.textStorage.string as NSString
        let fullRange  = NSRange(location: 0, length: fullString.length)
        var ranges: [NSRange] = []
        var searchRange = fullRange

        while searchRange.location < NSMaxRange(fullRange) {
            let found = fullString.range(
                of: trimmed,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            let nextStart = found.location + max(found.length, 1)
            searchRange = NSRange(location: nextStart, length: fullRange.length - nextStart)
        }

        searchRanges = ranges
        guard !ranges.isEmpty else { return 0 }

        currentSearchIndex = 0
        highlightCurrentMatch(in: tv)
        return ranges.count
    }

    /// Advances to the next match (wrapping) and scrolls it into view.
    /// Returns the new 0-based index so the caller can update a counter.
    @discardableResult
    func goToNextMatch() -> Int {
        guard !searchRanges.isEmpty, let tv = textView else { return 0 }
        currentSearchIndex = (currentSearchIndex + 1) % searchRanges.count
        highlightCurrentMatch(in: tv)
        return currentSearchIndex
    }

    /// Moves to the previous match (wrapping) and scrolls it into view.
    /// Returns the new 0-based index.
    @discardableResult
    func goToPreviousMatch() -> Int {
        guard !searchRanges.isEmpty, let tv = textView else { return 0 }
        currentSearchIndex = (currentSearchIndex - 1 + searchRanges.count) % searchRanges.count
        highlightCurrentMatch(in: tv)
        return currentSearchIndex
    }

    /// Removes all search highlights. Safe to call when no search is active.
    func clearSearchHighlights() {
        guard let tv = textView else {
            searchRanges = []
            currentSearchIndex = 0
            return
        }
        if let tlm = tv.textLayoutManager {
            // TextKit 2 path: wipe rendering attributes over the whole document.
            tlm.removeRenderingAttribute(.backgroundColor, for: tlm.documentRange)
        } else if !searchRanges.isEmpty {
            // TextKit 1 fallback (shouldn't occur; tv was created with usingTextLayoutManager: true).
            let fullRange = NSRange(location: 0, length: tv.textStorage.length)
            tv.textStorage.beginEditing()
            tv.textStorage.removeAttribute(.backgroundColor, range: fullRange)
            tv.textStorage.endEditing()
        }
        searchRanges = []
        currentSearchIndex = 0
    }

    // Repaints all matches yellow, the active match orange, then scrolls to it.
    // Uses TextKit 2 rendering attributes so highlights never touch the backing
    // store and autosave is never triggered.
    private func highlightCurrentMatch(in tv: UITextView) {
        guard !searchRanges.isEmpty else { return }

        if let tlm = tv.textLayoutManager {
            // Clear previous rendering highlights for the whole document.
            tlm.removeRenderingAttribute(.backgroundColor, for: tlm.documentRange)
            // Paint all matches yellow.
            for range in searchRanges {
                if let tr = nsTextRange(for: range, in: tlm) {
                    tlm.addRenderingAttribute(.backgroundColor,
                                             value: searchHighlightColor, for: tr)
                }
            }
            // Paint the active match orange.
            let activeRange = searchRanges[currentSearchIndex]
            if let tr = nsTextRange(for: activeRange, in: tlm) {
                tlm.addRenderingAttribute(.backgroundColor,
                                         value: searchActiveHighlightColor, for: tr)
            }
            scrollToMatch(activeRange, in: tv)
        } else {
            // TextKit 1 fallback.
            tv.textStorage.beginEditing()
            for range in searchRanges {
                tv.textStorage.addAttribute(.backgroundColor,
                                           value: searchHighlightColor, range: range)
            }
            let activeRange = searchRanges[currentSearchIndex]
            tv.textStorage.addAttribute(.backgroundColor,
                                        value: searchActiveHighlightColor, range: activeRange)
            tv.textStorage.endEditing()
            scrollToMatch(activeRange, in: tv)
        }
    }

    /// Converts an `NSRange` into an `NSTextRange` using the TextKit 2 content manager.
    private func nsTextRange(for nsRange: NSRange,
                             in tlm: NSTextLayoutManager) -> NSTextRange? {
        guard let cm = tlm.textContentManager else { return nil }
        guard
            let start = cm.location(cm.documentRange.location, offsetBy: nsRange.location),
            let end   = cm.location(start, offsetBy: nsRange.length)
        else { return nil }
        return NSTextRange(location: start, end: end)
    }

    /// Walks the view hierarchy above `tv` to find the UIScrollView that backs
    /// SwiftUI's ScrollView — the real scroller when isScrollEnabled is false.
    private func enclosingScrollView() -> UIScrollView? {
        var view: UIView? = textView?.superview
        while let v = view {
            if let sv = v as? UIScrollView { return sv }
            view = v.superview
        }
        return nil
    }

    /// Scrolls the enclosing UIScrollView so `range` is visible, with vertical padding
    /// so the match doesn't land flush against the header or the bottom edge.
    private func scrollToMatch(_ range: NSRange, in tv: UITextView) {
        guard let sv = enclosingScrollView() else {
            tv.scrollRangeToVisible(range)   // fallback: tv is somehow self-scrolling
            return
        }

        // Build a UITextRange via TextKit 2-safe position APIs.
        guard
            let start  = tv.position(from: tv.beginningOfDocument, offset: range.location),
            let end    = tv.position(from: start, offset: range.length),
            let tRange = tv.textRange(from: start, to: end)
        else { return }

        // firstRect(for:) gives the rect in the text view's coordinate space.
        // Guard against null / infinite results (can occur before layout finishes).
        let matchRectInTV = tv.firstRect(for: tRange)
        guard matchRectInTV != .null,
              matchRectInTV.width.isFinite,
              matchRectInTV.height.isFinite else { return }

        // Convert and add breathing room so the match isn't hidden under the
        // search bar header (top) or barely peeking above the bottom edge.
        let matchRectInSV = tv.convert(matchRectInTV, to: sv)
        sv.scrollRectToVisible(matchRectInSV.insetBy(dx: 0, dy: -60), animated: true)
    }
}

// MARK: - UIFont trait toggle helper

private extension UIFont {
    func toggling(_ trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let desc = fontDescriptor
        var traits = desc.symbolicTraits
        if traits.contains(trait) {
            traits.remove(trait)
        } else {
            traits.insert(trait)
        }
        let newDesc = desc.withSymbolicTraits(traits) ?? desc
        return UIFont(descriptor: newDesc, size: pointSize)
    }
}

// MARK: - RichTextEditor (UIViewRepresentable)

struct RichTextEditor<Accessory: View>: UIViewRepresentable {
    @ObservedObject var controller: RichTextController
    var accessory: () -> Accessory

    init(controller: RichTextController, @ViewBuilder accessory: @escaping () -> Accessory) {
        self._controller = ObservedObject(wrappedValue: controller)
        self.accessory = accessory
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView(usingTextLayoutManager: true)
        tv.delegate = context.coordinator
        tv.font = UIFont(name: "HelveticaNeue", size: 15) ?? .systemFont(ofSize: 15)
        tv.textColor = .label
        tv.typingAttributes[.foregroundColor] = UIColor.label
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        // Bind the text container's width to the view's width so long lines
        // wrap at the edge rather than overflowing horizontally.
        tv.textContainer.widthTracksTextView = true
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.attributedText = controller.attributedText
        // TextKit 2 renders runs with no explicit foreground color as black.
        // Stamp every character with UIColor.label immediately after load.
        controller.normalizeForegroundColor(tv)
        // Prevent UITextView from self-scrolling when content is assigned.
        // The outer SwiftUI ScrollView is the sole scroller; the text view
        // must always start at offset zero so the top lines aren't hidden
        // under the header when a note is opened.
        tv.contentOffset = .zero
        controller.textView = tv

        // Tap recognizer for caret placement on attachment padding and the empty area
        // below content. cancelsTouchesInView=false lets attachment interactive subviews
        // (image, card buttons, table cells) still handle their own taps unimpeded.
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        tv.addGestureRecognizer(tap)

        // Fix legacy notes that were persisted ending directly on an attachment.
        controller.ensureTrailingTextSlot()

        let host = UIHostingController(rootView: accessory())
        host.view.frame = CGRect(x: 0, y: 0, width: 0, height: 48)
        host.view.autoresizingMask = [.flexibleWidth]
        host.view.backgroundColor = .clear
        tv.inputAccessoryView = host.view
        context.coordinator.hostingController = host

        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        // Only sync when changed externally (e.g. on appear load), not while user types
        if tv.attributedText != controller.attributedText && !context.coordinator.isEditing {
            let savedRange = tv.selectedRange
            tv.attributedText = controller.attributedText
            // Stamp label color on the freshly loaded content so colorless runs
            // (notes saved before the color fix) don't render black in dark mode.
            controller.normalizeForegroundColor(tv)
            tv.selectedRange = savedRange
            // Reset any self-scroll that occurred during content load so the
            // outer SwiftUI ScrollView always controls the view position.
            tv.contentOffset = .zero
        }
        context.coordinator.hostingController?.rootView = accessory()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        let controller: RichTextController
        var isEditing = false
        var hostingController: UIHostingController<Accessory>?

        init(controller: RichTextController) {
            self.controller = controller
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            // Intercept Return key to auto-continue or exit list items.
            if text == "\n", controller.handleNewline(at: range) { return false }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            controller.sync(from: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
            controller.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            controller.isFocused = false
        }

        // Fires on every caret/selection change — the single chokepoint where we
        // reassert the label color so UIKit's typingAttributes re-derivation from
        // a colorless attachment glyph can never make newly typed text go black.
        func textViewDidChangeSelection(_ textView: UITextView) {
            textView.typingAttributes[.foregroundColor] = UIColor.label
        }

        // UIScrollViewDelegate: UITextView fires scroll-to-visible internally (e.g.
        // on content assignment or caret moves) even when isScrollEnabled is false.
        // Pinning the offset to zero ensures the outer SwiftUI ScrollView remains the
        // sole scroller and the note always opens at the top.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if !scrollView.isScrollEnabled, scrollView.contentOffset != .zero {
                scrollView.contentOffset = .zero
            }
        }

        // MARK: Caret placement

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let tv = controller.textView else { return }
            controller.placeCaret(at: g.location(in: tv))
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            // Allow caret placement on the text view's own background and on the
            // transparent top-padding area of attachment containers. Taps on interactive
            // inner subviews (image views, card buttons, sliders, table cells) are NOT
            // AttachmentContainerView instances, so they keep handling their own taps.
            return touch.view === controller.textView || touch.view is AttachmentContainerView
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Let UITextInteraction (caret, magnifier, double-tap selection) run
            // alongside our recognizer without either cancelling the other.
            return true
        }
    }
}

// MARK: - AttachmentContainerView

/// Marker UIView subclass used as the root container of every non-text attachment
/// view provider (image, file, audio, table). Taps on this view — the bare top-
/// padding area between blocks — reach `Coordinator.shouldReceive`, which passes
/// them to `placeCaret(at:)`. Taps on the inner interactive subviews (image view,
/// card buttons, table text fields, slider) are NOT an `AttachmentContainerView`
/// touch, so `shouldReceive` rejects them and those subviews handle their own taps.
final class AttachmentContainerView: UIView {}
