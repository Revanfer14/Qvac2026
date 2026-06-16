//
//  NoteEditorBody.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 16/06/26.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct NoteEditorBody: View {

    @ObservedObject var state: NoteEditorState
    var onMoveToTrash: () -> Void

    @Environment(\.dismiss) private var dismiss
    private let db = DatabaseService.shared

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
                        if state.isRecording {
                            listeningPill.padding(.top, 10)
                        }
                        attachmentSection.padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 140)
                }
            }

            if !state.editor.isFocused {
                floatingBar.padding(.bottom, 28)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                keyboardBar
            }
        }
        .alert("Rename Note", isPresented: $state.showRename) {
            TextField("Title", text: $state.renameText)
            Button("Save") { state.noteTitle = state.renameText }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $state.showPhotoPicker, selection: $state.selectedPhotos, matching: .images)
        .onChange(of: state.selectedPhotos) { _, items in
            Task { @MainActor in
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        state.displayImages.append(DisplayImage(id: UUID(), image: img))
                    }
                }
                state.selectedPhotos = []
            }
        }
        .fileImporter(isPresented: $state.showFilePicker, allowedContentTypes: [.data]) { result in
            guard let url = try? result.get() else { return }
            state.fileAttachments.append(Attachment(
                noteId:    state.noteId,
                type:      .file,
                filename:  url.lastPathComponent,
                filePath:  url.path,
                sizeBytes: 0,
                createdAt: .now
            ))
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
                Text(state.noteTitle)
                    .font(.custom("HelveticaNeue-Bold", size: 20))
                    .foregroundStyle(.primary)
                Text(state.formattedDate)
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if state.editor.isFocused {
                Button {
                    state.editor.textView?.resignFirstResponder()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }
            } else {
                Menu {
                    Button { } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    Button { state.renameText = state.noteTitle; state.showRename = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) {
                        onMoveToTrash()
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
            if state.editor.isEmpty {
                Text("Type [ / ] to insert formatting and [ @ ] to link a note")
                    .font(.custom("HelveticaNeue", size: 15))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .allowsHitTesting(false)
            }
            RichTextEditor(controller: state.editor)
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
        if !state.displayImages.isEmpty || !state.fileAttachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if !state.displayImages.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140, maximum: 200))],
                        spacing: 8
                    ) {
                        ForEach(state.displayImages) { item in
                            Image(uiImage: item.image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                ForEach(state.fileAttachments) { att in
                    AttachmentRowView(attachment: att) {
                        if state.persistedAttachmentIds.contains(att.id) {
                            db.attachments.delete(id: att.id)
                        }
                        state.fileAttachments.removeAll { $0.id == att.id }
                    }
                }
            }
        }
    }

    // MARK: - Floating Bar (keyboard not visible)

    private var floatingBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                Button { state.editor.textView?.becomeFirstResponder() } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.bluePrimary)
                }
                icon("mic")                { state.editor.textView?.becomeFirstResponder(); state.startRecording() }
                icon("camera")              {}
                icon("photo.on.rectangle")  { state.showPhotoPicker = true }
                icon("paperclip")           { state.showFilePicker  = true }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [Color.white.opacity(0), Color.white.opacity(0.9)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 50)
            .allowsHitTesting(false)
        }
        .frame(height: 48)
        .background(Color.white)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(hex: "#DCDCDC"), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 2)
    }

    // MARK: - Keyboard Toolbar

    @ViewBuilder
    private var keyboardBar: some View {
        switch state.activeToolbar {
        case .main:       mainBar
        case .formatting: formattingBar
        case .list:       listBar
        case .recording:  recordingBar
        }
    }

    private var mainBar: some View {
        HStack(spacing: 18) {
            Button {} label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.bluePrimary)
            }
            icon("mic")                  { state.startRecording() }
            icon("camera")                {}
            icon("photo.on.rectangle")    { state.showPhotoPicker = true }
            icon("paperclip")             { state.showFilePicker  = true }
            Color.secondary.opacity(0.25)
                .frame(width: 1, height: 18)
            icon("textformat.alt")        { state.activeToolbar = .formatting }
            icon("list.bullet")           { state.activeToolbar = .list }
            icon("tablecells")            { state.editor.insertTable() }
            icon("arrow.uturn.backward")  { state.editor.undo() }
            icon("arrow.uturn.forward")   { state.editor.redo() }
        }
    }

    private var formattingBar: some View {
        HStack(spacing: 0) {
            Button { state.activeToolbar = .main } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 26, height: 26)
            }
            Spacer()
            Button("H1") { state.editor.applyHeading(1) }
                .font(.custom("HelveticaNeue-Bold", size: 14))
                .foregroundStyle(.primary)
            Spacer()
            Button("H2") { state.editor.applyHeading(2) }
                .font(.custom("HelveticaNeue-Bold", size: 14))
                .foregroundStyle(.primary)
            Spacer()
            Button("H3") { state.editor.applyHeading(3) }
                .font(.custom("HelveticaNeue-Bold", size: 14))
                .foregroundStyle(.primary)
            Spacer()
            icon("bold")            { state.editor.toggleBold() }
            Spacer()
            icon("italic")          { state.editor.toggleItalic() }
            Spacer()
            icon("underline")       { state.editor.toggleUnderline() }
            Spacer()
            icon("strikethrough")   { state.editor.toggleStrikethrough() }
            Spacer()
            icon("decrease.indent") { state.editor.indentDecrease() }
            Spacer()
            icon("increase.indent") { state.editor.indentIncrease() }
        }
    }

    private var listBar: some View {
        HStack(spacing: 0) {
            Button { state.activeToolbar = .main } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 26, height: 26)
            }
            Spacer()
            icon("list.bullet") { state.editor.toggleBulletList() }
            Spacer()
            icon("checklist")   { state.editor.toggleChecklist() }
            Spacer()
            icon("list.number") { state.editor.toggleNumberedList() }
            Spacer()
        }
    }

    private var recordingBar: some View {
        HStack(spacing: 12) {
            Text(state.recordingTimeString)
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

            Button { state.cancelRecording() } label: {
                Text("Cancel")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }

            Button { state.stopRecording() } label: {
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
}
