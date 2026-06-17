//
//  NoteEditorViewModel.swift
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

// MARK: - NoteEditorViewModel

@MainActor
final class NoteEditorViewModel: ObservableObject {

    // MARK: Note identity

    let noteId: UUID
    @Published var noteTitle: String
    @Published var updatedAt: Date?

    // MARK: Rich-text editor

    let editor = RichTextController()

    // MARK: Attachments (non-audio only; audio lives inline in the text body)

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
    private var currentRecordingFilename: String?
    private let audioRecorder = AudioRecorderService()

    // MARK: Pickers

    @Published var showPhotoPicker = false
    @Published var selectedPhotos: [PhotosPickerItem] = []
    @Published var showFilePicker  = false

    // MARK: Persistence flags

    private var persistedNoteExists: Bool
    private var suppressAutosave    = false
    private var hasChanges          = false
    private var titleWasManuallySet = false

    // MARK: Editor republish

    private var editorCancellable: AnyCancellable?

    // MARK: Init

    init(blankWithId id: UUID = UUID()) {
        self.noteId    = id
        self.noteTitle = "Untitled Note"
        self.updatedAt = nil
        self.persistedNoteExists = false
        bindEditor()
    }

    init(note: Note) {
        self.noteId    = note.id
        self.noteTitle = note.title
        self.updatedAt = note.updatedAt
        self.persistedNoteExists    = true
        self.titleWasManuallySet    = note.title != "Untitled Note"
        bindEditor()
    }

    private func bindEditor() {
        editorCancellable = editor.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: Content loading

    /// Loads note content into the editor and reconnects audio attachment hosts.
    /// Replaces direct calls to `editor.loadInitialContent` in the views.
    func loadContent(note: Note?) {
        editor.loadInitialContent(note: note)
        if note != nil {
            loadPersistedAttachments()
        }
        // Reconnect host on any AudioTextAttachments restored from the archive
        editor.attributedText.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: editor.attributedText.length),
            options: []
        ) { [weak self] value, _, _ in
            (value as? AudioTextAttachment)?.host = self
        }
    }

    // MARK: Persistence

    func persist() {
        guard !suppressAutosave else { return }

        // Strip object-replacement chars (inline attachments) for text-only columns
        let plain = editor.attributedText.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
        let hasInlineAudio = editor.attributedText.string.contains("\u{FFFC}")
        let trimmedEmpty = plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if trimmedEmpty && !hasInlineAudio && !persistedNoteExists { return }

        // Auto-derive title from first non-empty line until the user manually renames.
        if !titleWasManuallySet {
            let derived = Self.derivedTitle(from: plain)
            if derived != noteTitle { noteTitle = derived }
        }

        let preview = String(plain.prefix(100))

        // Persist the attributed string with NSKeyedArchiver so inline audio
        // attachments (AudioTextAttachment) round-trip correctly.
        let bodyData = try? NSKeyedArchiver.archivedData(
            withRootObject: editor.attributedText,
            requiringSecureCoding: false
        )

        let db = DatabaseService.shared
        if persistedNoteExists {
            db.notes.rename(id: noteId, title: noteTitle)
            db.notes.updateContent(id: noteId, content: plain, contentRTF: bodyData, preview: preview)
        } else {
            db.notes.insert(Note(
                id:         noteId,
                title:      noteTitle,
                preview:    preview,
                content:    plain,
                contentRTF: bodyData,
                type:       .text,
                createdAt:  .now,
                updatedAt:  .now
            ))
            persistedNoteExists = true
        }
        updatedAt = .now
        flushNewAttachments()
        hasChanges = false
    }

    private static func derivedTitle(from text: String) -> String {
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !firstLine.isEmpty else { return "Untitled Note" }
        return String(firstLine.prefix(50))
    }

    func persistIfChanged() {
        if hasChanges { persist() }
    }

    /// Called from the Rename alert. Locks the title so body edits no longer overwrite it.
    func applyManualRename(_ newTitle: String) {
        titleWasManuallySet = true
        noteTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func markChanged() {
        hasChanges = true
    }

    func moveToTrash() {
        suppressAutosave = true
        DatabaseService.shared.notes.moveToTrash(id: noteId)
    }

    // MARK: Attachments (files/images — audio is handled separately inline)

    func loadPersistedAttachments() {
        let loaded = DatabaseService.shared.attachments.fetch(forNoteId: noteId)
        // Audio attachments live inline in the note body; exclude them from the bottom section
        fileAttachments = loaded.filter { $0.type != .image && $0.type != .audio }
        persistedAttachmentIds = Set(loaded.map { $0.id })
    }

    func deleteAttachment(_ att: Attachment) {
        if persistedAttachmentIds.contains(att.id) {
            DatabaseService.shared.attachments.delete(id: att.id)
        }
        fileAttachments.removeAll { $0.id == att.id }
    }

    private func flushNewAttachments() {
        let attachments = DatabaseService.shared.attachments
        for att in fileAttachments where !persistedAttachmentIds.contains(att.id) {
            attachments.insert(att)
            persistedAttachmentIds.insert(att.id)
        }
    }

    // MARK: Recording

    func startRecording() {
        Task {
            let granted = await audioRecorder.requestPermission()
            guard granted else { return }
            do {
                let filename = try audioRecorder.start()
                currentRecordingFilename = filename
            } catch {
                print("NoteEditorViewModel: recorder start error: \(error)")
                return
            }
            isRecording = true
            activeToolbar = .recording
            recordingSeconds = 0
            recordingTimer?.invalidate()
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                MainActor.assumeIsolated { self.recordingSeconds += 1 }
            }
        }
    }

    func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        activeToolbar = .main

        guard let filename = currentRecordingFilename else { return }
        currentRecordingFilename = nil

        let (durationMs, sizeBytes) = audioRecorder.stop()
        let attachment = Attachment(
            noteId:     noteId,
            type:       .audio,
            filename:   filename,
            filePath:   filename,      // relative name resolved via AudioService.url(forRelative:)
            sizeBytes:  sizeBytes,
            durationMs: max(durationMs, recordingSeconds * 1000),
            createdAt:  .now
        )

        // Persist the attachment row immediately (inline insert + body archive happen in persist())
        DatabaseService.shared.attachments.insert(attachment)
        persistedAttachmentIds.insert(attachment.id)

        // Insert the card inline in the editor and save
        editor.insertAudio(attachment, host: self)
        markChanged()
        persist()
    }

    func cancelRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        activeToolbar = .main
        audioRecorder.cancel()
        currentRecordingFilename = nil
    }

    // MARK: Formatting helpers

    var recordingTimeString: String {
        String(format: "%d:%02d", recordingSeconds / 60, recordingSeconds % 60)
    }

    var formattedDate: String {
        guard let date = updatedAt else { return "Not saved yet" }
        let fmt = DateFormatter()
        fmt.dateFormat = Calendar.current.isDateInToday(date)
            ? "'Last updated, Today,' HH:mm"
            : "'Last updated,' MMM d, HH:mm"
        return fmt.string(from: date)
    }
}

// MARK: - AudioAttachmentHosting

extension NoteEditorViewModel: AudioAttachmentHosting {

    func deleteInlineAudio(id: UUID) {
        // Look up the attachment to get the file path before deleting the DB row
        if let att = DatabaseService.shared.attachments.fetch(id: id) {
            DatabaseService.shared.attachments.delete(id: id)
            AudioService.delete(relativeName: att.filePath)
        }
        persistedAttachmentIds.remove(id)
        editor.removeAudioAttachment(audioId: id.uuidString)
        markChanged()
        persist()
    }
}
