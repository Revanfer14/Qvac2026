//
//  NoteDetailView.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 14/06/26.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit
import Combine

// MARK: - Supporting types

private enum NoteToolbarMode { case main, formatting, list, recording }

private struct DisplayImage: Identifiable {
    let id: UUID
    let image: UIImage
}

// MARK: - NoteDetailView

struct NoteDetailView: View {

    var note: Note?

    init(note: Note? = nil) {
        self.note    = note
        _noteId      = State(initialValue: note?.id      ?? UUID())
        _noteTitle   = State(initialValue: note?.title   ?? "Untitled Note")
        _updatedAt   = State(initialValue: note?.updatedAt ?? .now)
        _persistedNoteExists = State(initialValue: note != nil)
    }

    // MARK: Env

    @Environment(\.dismiss) private var dismiss
    private let db = DatabaseService.shared

    // MARK: Note

    @State private var noteId:    UUID
    @State private var noteTitle: String
    @State private var updatedAt: Date

    // MARK: Rich-text editor

    @StateObject private var editor = RichTextController()

    // MARK: Attachments

    @State private var fileAttachments:        [Attachment] = []
    @State private var displayImages:          [DisplayImage] = []
    @State private var persistedAttachmentIds: Set<UUID> = []

    // MARK: Save guard

    @State private var persistedNoteExists: Bool
    @State private var suppressAutosave    = false
    @State private var autosaveCancellable: AnyCancellable?

    // MARK: UI

    @State private var activeToolbar = NoteToolbarMode.main
    @State private var showRename    = false
    @State private var renameText    = ""

    // MARK: Recording

    @State private var isRecording      = false
    @State private var recordingSeconds = 0
    @State private var recordingTimer:  Timer?

    // MARK: Pickers

    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showFilePicker  = false

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()

            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        contentEditor
                        if isRecording {
                            listeningPill.padding(.top, 10)
                        }
                        attachmentSection.padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 140)
                }
            }

            if !editor.isFocused {
                floatingBar.padding(.bottom, 28)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                keyboardBar
            }
        }
        .alert("Rename Note", isPresented: $showRename) {
            TextField("Title", text: $renameText)
            Button("Save") { noteTitle = renameText }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotos, matching: .images)
        .onChange(of: selectedPhotos) { _, items in
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        let entry = DisplayImage(id: UUID(), image: img)
                        displayImages.append(entry)
                    }
                }
                selectedPhotos = []
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data]) { result in
            guard let url = try? result.get() else { return }
            fileAttachments.append(Attachment(
                noteId:    noteId,
                type:      .file,
                filename:  url.lastPathComponent,
                filePath:  url.path,
                sizeBytes: 0,
                createdAt: .now
            ))
        }
        .onAppear {
            editor.loadInitialContent(note: note)
            if let existing = note {
                let loaded = db.attachments.fetch(forNoteId: existing.id)
                fileAttachments = loaded.filter { $0.type != .image }
                persistedAttachmentIds = Set(loaded.map { $0.id })
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    editor.textView?.becomeFirstResponder()
                }
            }
            autosaveCancellable = editor.$attributedText
                .dropFirst()
                .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
                .sink { _ in persistNote() }
        }
        .onChange(of: noteTitle) { _, _ in persistNote() }
        .onDisappear {
            persistNote()
        }
    }

    // MARK: - Persistence

    private func persistNote() {
        guard !suppressAutosave else { return }
        let plain = editor.attributedText.string
        let trimmedEmpty = plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if trimmedEmpty && !persistedNoteExists { return }

        let preview = String(plain.prefix(100))
        let rtfData = try? editor.attributedText.data(
            from: NSRange(location: 0, length: editor.attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        if persistedNoteExists {
            db.notes.rename(id: noteId, title: noteTitle)
            db.notes.updateContent(id: noteId, content: plain, contentRTF: rtfData, preview: preview)
        } else {
            db.notes.insert(Note(
                id:         noteId,
                title:      noteTitle,
                preview:    preview,
                content:    plain,
                contentRTF: rtfData,
                type:       .text,
                createdAt:  .now,
                updatedAt:  .now
            ))
            persistedNoteExists = true
        }
        updatedAt = .now

        for att in fileAttachments where !persistedAttachmentIds.contains(att.id) {
            db.attachments.insert(Attachment(
                id:         att.id,
                noteId:     noteId,
                type:       att.type,
                filename:   att.filename,
                filePath:   att.filePath,
                mimeType:   att.mimeType,
                sizeBytes:  att.sizeBytes,
                durationMs: att.durationMs,
                transcript: att.transcript,
                createdAt:  att.createdAt
            ))
            persistedAttachmentIds.insert(att.id)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(noteTitle)
                    .font(.custom("HelveticaNeue-Bold", size: 20))
                    .foregroundStyle(.primary)
                Text(formattedDate)
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if editor.isFocused {
                Button {
                    editor.textView?.resignFirstResponder()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }
            } else {
                Menu {
                    Button { } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    Button { renameText = noteTitle; showRename = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        suppressAutosave = true
                        db.notes.moveToTrash(id: noteId)
                        dismiss()
                    } label: { Label("Move to Trash", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .rotationEffect(.degrees(90))
                        .frame(width: 28, height: 28)
                }
            }
        }
    }

    // MARK: - Content Editor

    private var contentEditor: some View {
        ZStack(alignment: .topLeading) {
            if editor.isEmpty {
                Text("Type [ / ] to insert formatting and [ @ ] to link a note")
                    .font(.custom("HelveticaNeue", size: 15))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .allowsHitTesting(false)
            }
            RichTextEditor(controller: editor)
                .frame(minHeight: 200)
        }
    }

    // MARK: - Listening Pill

    private var listeningPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("Listening ...")
                .font(.custom("HelveticaNeue", size: 14))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Attachments

    @ViewBuilder
    private var attachmentSection: some View {
        if !displayImages.isEmpty || !fileAttachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !displayImages.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140, maximum: 200))],
                        spacing: 8
                    ) {
                        ForEach(displayImages) { item in
                            Image(uiImage: item.image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                ForEach(fileAttachments) { att in
                    AttachmentRowView(attachment: att) {
                        if persistedAttachmentIds.contains(att.id) {
                            db.attachments.delete(id: att.id)
                        }
                        fileAttachments.removeAll { $0.id == att.id }
                    }
                }
            }
        }
    }

    // MARK: - Floating Bar (keyboard not visible)

    private var floatingBar: some View {
        HStack(spacing: 20) {
            Button { editor.textView?.becomeFirstResponder() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.bluePrimary)
                    .clipShape(Circle())
            }
            icon("mic")                { editor.textView?.becomeFirstResponder(); startRecording() }
            icon("camera")              {}
            icon("photo.on.rectangle")  { showPhotoPicker = true }
            icon("paperclip")           { showFilePicker  = true }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(Color.cardBackground)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 4)
    }

    // MARK: - Keyboard Toolbar

    @ViewBuilder
    private var keyboardBar: some View {
        switch activeToolbar {
        case .main:       mainBar
        case .formatting: formattingBar
        case .list:       listBar
        case .recording:  recordingBar
        }
    }

    private var mainBar: some View {
        HStack(spacing: 0) {
            Button {} label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.bluePrimary)
                    .clipShape(Circle())
            }
            Spacer()
            icon("mic")               { startRecording() }
            Spacer()
            icon("camera")             {}
            Spacer()
            icon("photo.on.rectangle") { showPhotoPicker = true }
            Spacer()
            icon("paperclip")          { showFilePicker  = true }
            Color.secondary.opacity(0.25)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 8)
            icon("textformat")  { activeToolbar = .formatting }
            Spacer()
            icon("list.bullet") { activeToolbar = .list }
            Spacer()
            icon("tablecells")  { editor.insertTable() }
            Spacer()
            Button {
                editor.textView?.resignFirstResponder()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 26, height: 26)
            }
        }
    }

    private var formattingBar: some View {
        HStack(spacing: 0) {
            Button { activeToolbar = .main } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 26, height: 26)
            }
            Spacer()
            Button("H1") { editor.applyHeading(1) }
                .font(.custom("HelveticaNeue-Bold", size: 14))
                .foregroundStyle(.primary)
            Spacer()
            Button("H2") { editor.applyHeading(2) }
                .font(.custom("HelveticaNeue-Bold", size: 14))
                .foregroundStyle(.primary)
            Spacer()
            Button("H3") { editor.applyHeading(3) }
                .font(.custom("HelveticaNeue-Bold", size: 14))
                .foregroundStyle(.primary)
            Spacer()
            icon("bold")            { editor.toggleBold() }
            Spacer()
            icon("italic")          { editor.toggleItalic() }
            Spacer()
            icon("underline")       { editor.toggleUnderline() }
            Spacer()
            icon("strikethrough")   { editor.toggleStrikethrough() }
            Spacer()
            icon("decrease.indent") { editor.indentDecrease() }
            Spacer()
            icon("increase.indent") { editor.indentIncrease() }
        }
    }

    private var listBar: some View {
        HStack(spacing: 0) {
            Button { activeToolbar = .main } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 26, height: 26)
            }
            Spacer()
            icon("list.bullet") { editor.toggleBulletList() }
            Spacer()
            icon("checklist")   { editor.toggleChecklist() }
            Spacer()
            icon("list.number") { editor.toggleNumberedList() }
            Spacer()
        }
    }

    private var recordingBar: some View {
        HStack(spacing: 12) {
            Text(recordingTimeString)
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(
                    Array([8, 14, 20, 12, 18, 22, 10, 16, 20, 8, 14, 18, 22, 12, 16, 10, 20, 14]
                        .enumerated()),
                    id: \.offset
                ) { _, h in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blueLight)
                        .frame(width: 3, height: CGFloat(h))
                }
            }

            Spacer()

            Button { cancelRecording() } label: {
                Text("Cancel")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }

            Button { stopRecording() } label: {
                Text("Done")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.bluePrimary)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func icon(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 26, height: 26)
        }
    }

    private var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = Calendar.current.isDateInToday(updatedAt)
            ? "'Last updated, Today,' HH:mm"
            : "'Last updated,' MMM d, HH:mm"
        return fmt.string(from: updatedAt)
    }

    private var recordingTimeString: String {
        String(format: "%d:%02d", recordingSeconds / 60, recordingSeconds % 60)
    }

    private func startRecording() {
        isRecording = true
        activeToolbar = .recording
        recordingSeconds = 0
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                recordingSeconds += 1
            }
        }
    }

    private func stopRecording() {
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

    private func cancelRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        activeToolbar = .main
    }
}

// MARK: - AttachmentRowView

struct AttachmentRowView: View {
    let attachment: Attachment
    let onDelete: () -> Void

    @State private var showRename = false
    @State private var renameText = ""

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor)
                    .frame(width: 32, height: 32)
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text(attachment.filename)
                .font(.custom("HelveticaNeue", size: 14))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Menu {
                if attachment.type == .audio {
                    Button { } label: {
                        Label("Transcribe", systemImage: "waveform.badge.mic")
                    }
                    Button { renameText = attachment.filename; showRename = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                }
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(90))
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .alert("Rename", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Save") {}
            Button("Cancel", role: .cancel) {}
        }
    }

    private var iconName: String {
        switch attachment.type {
        case .audio:  "play.fill"
        case .file:   "doc.fill"
        case .image:  "photo.fill"
        case .camera: "camera.fill"
        }
    }

    private var iconColor: Color {
        switch attachment.type {
        case .audio:          Color.bluePrimary
        case .file:           Color.blueMedium
        case .image, .camera: Color.blueLight
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NoteDetailView()
    }
}

#Preview("Existing Note") {
    NavigationStack {
        NoteDetailView(note: Note.samples[0])
    }
}
