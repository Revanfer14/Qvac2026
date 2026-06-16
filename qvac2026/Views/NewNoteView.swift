//
//  NewNoteView.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 16/06/26.
//

import SwiftUI
import Combine

struct NewNoteView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = NoteEditorState(blankWithId: UUID())

    @State private var persistedNoteExists = false
    @State private var suppressAutosave    = false
    @State private var autosaveCancellable: AnyCancellable?

    private let db = DatabaseService.shared

    var body: some View {
        NoteEditorBody(state: state, onMoveToTrash: trashAndDismiss)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                state.editor.loadInitialContent(note: nil)
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
        let trimmedEmpty = plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if trimmedEmpty && !persistedNoteExists { return }

        let preview = String(plain.prefix(100))
        let rtfData = try? state.editor.attributedText.data(
            from: NSRange(location: 0, length: state.editor.attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        if persistedNoteExists {
            db.notes.rename(id: state.noteId, title: state.noteTitle)
            db.notes.updateContent(id: state.noteId, content: plain, contentRTF: rtfData, preview: preview)
        } else {
            db.notes.insert(Note(
                id:         state.noteId,
                title:      state.noteTitle,
                preview:    preview,
                content:    plain,
                contentRTF: rtfData,
                type:       .text,
                createdAt:  .now,
                updatedAt:  .now
            ))
            persistedNoteExists = true
        }
        state.updatedAt = .now
        state.flushNewAttachments(db: db)
    }

    private func trashAndDismiss() {
        suppressAutosave = true
        db.notes.moveToTrash(id: state.noteId)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        NewNoteView()
    }
}
