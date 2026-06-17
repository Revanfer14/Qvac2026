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
            attributedText = NSAttributedString(string: plain, attributes: [.font: defaultFont])
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
            let insertion = NSAttributedString(string: prefix, attributes: [.font: defaultFont])
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

    func insertTable() {
        guard let tv = textView else { return }
        let tableTemplate = "| Col 1 | Col 2 |\n| --- | --- |\n| a | b |\n"
        let insertion = NSAttributedString(string: tableTemplate, attributes: [.font: defaultFont])
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        let insertionPoint = tv.selectedRange.location
        mutable.insert(insertion, at: insertionPoint)
        tv.attributedText = mutable
        tv.selectedRange = NSRange(location: insertionPoint + tableTemplate.utf16.count, length: 0)
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

        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: defaultFont]
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

        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: defaultFont]
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

        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: defaultFont]
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
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.attributedText = controller.attributedText
        controller.textView = tv

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
            tv.selectedRange = savedRange
        }
        context.coordinator.hostingController?.rootView = accessory()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, UITextViewDelegate {
        let controller: RichTextController
        var isEditing = false
        var hostingController: UIHostingController<Accessory>?

        init(controller: RichTextController) {
            self.controller = controller
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
    }
}
