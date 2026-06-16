//
//  NoteEditorState.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 16/06/26.
//

import SwiftUI
import PhotosUI
import UIKit
import Combine

// MARK: - Supporting types

enum NoteToolbarMode { case main, formatting, list, recording }

struct DisplayImage: Identifiable {
    let id: UUID
    let image: UIImage
}

// MARK: - NoteEditorState

@MainActor
final class NoteEditorState: ObservableObject {

    // MARK: Note identity

    let noteId: UUID
    @Published var noteTitle: String
    @Published var updatedAt: Date

    // MARK: Rich-text editor

    let editor = RichTextController()

    // MARK: Attachments

    @Published var fileAttachments:        [Attachment] = []
    @Published var displayImages:          [DisplayImage] = []
    @Published var persistedAttachmentIds: Set<UUID> = []

    // MARK: Toolbar / rename UI

    @Published var activeToolbar: NoteToolbarMode = .main
    @Published var showRename    = false
    @Published var renameText    = ""

    // MARK: Recording

    @Published var isRecording      = false
    @Published var recordingSeconds = 0
    private var recordingTimer: Timer?

    // MARK: Pickers

    @Published var showPhotoPicker = false
    @Published var selectedPhotos: [PhotosPickerItem] = []
    @Published var showFilePicker  = false

    // MARK: Editor republish

    private var editorCancellable: AnyCancellable?

    // MARK: Init

    init(blankWithId id: UUID = UUID()) {
        self.noteId    = id
        self.noteTitle = "Untitled Note"
        self.updatedAt = .now
        bindEditor()
    }

    init(note: Note) {
        self.noteId    = note.id
        self.noteTitle = note.title
        self.updatedAt = note.updatedAt
        bindEditor()
    }

    private func bindEditor() {
        editorCancellable = editor.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: Attachment flush

    func flushNewAttachments(db: DatabaseService) {
        for att in fileAttachments where !persistedAttachmentIds.contains(att.id) {
            db.attachments.insert(att)
            persistedAttachmentIds.insert(att.id)
        }
    }

    // MARK: Recording helpers

    func startRecording() {
        isRecording = true
        activeToolbar = .recording
        recordingSeconds = 0
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                self.recordingSeconds += 1
            }
        }
    }

    func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        let secs = recordingSeconds
        isRecording = false
        activeToolbar = .main
        fileAttachments.append(Attachment(
            noteId:     noteId,
            type:       .audio,
            filename:   "Rec\(Int(Date().timeIntervalSince1970)).mp3",
            filePath:   "",
            sizeBytes:  0,
            durationMs: secs * 1000,
            createdAt:  .now
        ))
    }

    func cancelRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        activeToolbar = .main
    }

    // MARK: Formatting

    var recordingTimeString: String {
        String(format: "%d:%02d", recordingSeconds / 60, recordingSeconds % 60)
    }

    var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = Calendar.current.isDateInToday(updatedAt)
            ? "'Last updated, Today,' HH:mm"
            : "'Last updated,' MMM d, HH:mm"
        return fmt.string(from: updatedAt)
    }
}
