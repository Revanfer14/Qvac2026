//
//  NoteDetailView.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 14/06/26.
//

import SwiftUI
import Combine

struct NoteDetailView: View {

    let note: Note

    @Environment(\.dismiss) private var dismiss
    @StateObject private var state: NoteEditorState

    @State private var suppressAutosave    = false
    @State private var autosaveCancellable: AnyCancellable?

    private let db = DatabaseService.shared

    init(note: Note) {
        self.note = note
        _state = StateObject(wrappedValue: NoteEditorState(note: note))
    }

    var body: some View {
        NoteEditorBody(state: state, onMoveToTrash: trashAndDismiss)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                state.editor.loadInitialContent(note: note)
                let loaded = db.attachments.fetch(forNoteId: note.id)
                state.fileAttachments = loaded.filter { $0.type != .image }
                state.persistedAttachmentIds = Set(loaded.map { $0.id })
                autosaveCancellable = state.editor.$attributedText
                    .dropFirst()
                    .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
                    .sink { _ in persist() }
            }
            .onChange(of: state.noteTitle) { _, _ in persist() }
            .onDisappear {
                state.editor.textView?.resignFirstResponder()
                state.editor.isFocused = false
                state.activeToolbar = .main
                persist()
            }
    }

    // MARK: - Persistence

    private func persist() {
        guard !suppressAutosave else { return }
        let plain = state.editor.attributedText.string
        let preview = String(plain.prefix(100))
        let rtfData = try? state.editor.attributedText.data(
            from: NSRange(location: 0, length: state.editor.attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        db.notes.rename(id: note.id, title: state.noteTitle)
        db.notes.updateContent(id: note.id, content: plain, contentRTF: rtfData, preview: preview)
        state.updatedAt = .now
        state.flushNewAttachments(db: db)
    }

    private func trashAndDismiss() {
        suppressAutosave = true
        db.notes.moveToTrash(id: note.id)
        dismiss()
    }
}

#Preview("Existing Note") {
    NavigationStack {
        NoteDetailView(note: Note.samples[0])
    }
}
