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

    @ObservedObject var state: NoteEditorViewModel
    var onMoveToTrash: () -> Void

    @Environment(\.dismiss) private var dismiss

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
        .alert("Rename Note", isPresented: $state.showRename) {
            TextField("Title", text: $state.renameText)
            Button("Save") { state.applyManualRename(state.renameText) }
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
            RichTextEditor(controller: state.editor) {
                NoteKeyboardToolbar(state: state)
            }
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
                        state.deleteAttachment(att)
                    }
                }
            }
        }
    }

    // MARK: - Floating Bar (keyboard not visible)

    private var floatingBar: some View {
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
        .fixedSize()
        .background(Color.white)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(hex: "#DCDCDC"), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 2)
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
        .buttonStyle(.plain)
    }
}
