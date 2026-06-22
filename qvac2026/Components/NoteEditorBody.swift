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

                if state.isSearching {
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                GeometryReader { geo in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            contentEditor
                            if state.isRecording {
                                listeningPill.padding(.top, 10)
                            }
                            // Tappable filler — routes taps on empty space below the last
                            // block to the text view, placing the caret at the end.
                            Color.clear
                                .frame(minHeight: 140, maxHeight: .infinity)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture { state.editor.focusAtEnd() }
                        }
                        .padding(.horizontal, 20)
                        // Ensures short notes fill the viewport so the filler expands
                        // to cover all empty space; long notes scroll normally.
                        .frame(minHeight: geo.size.height, alignment: .top)
                    }
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
                        state.addImage(img)
                    }
                }
                state.selectedPhotos = []
            }
        }
        .fullScreenCover(isPresented: $state.showCameraPicker) {
            CameraPicker { img in state.addImage(img) }
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $state.presentedImage) { item in
            ImageViewerView(image: item.image)
        }
        .sheet(item: $state.presentedFile) { file in
            FilePreviewView(url: file.url)
        }
        .fileImporter(isPresented: $state.showFilePicker, allowedContentTypes: [.data]) { result in
            guard let url = try? result.get() else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            state.addFile(from: url)
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
                    // Resign whichever UIResponder is currently active —
                    // works for both the main text view and table cell fields.
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }
            } else {
                HStack(spacing: 4) {
                    Button { state.openSearch() } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 28, height: 28)
                    }

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
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            // Query field (reuses the existing SearchBar component for consistent styling).
            SearchBar(text: $state.searchQuery)
                .onChange(of: state.searchQuery) { _, _ in state.runSearch() }

            // Match counter.
            if state.matchCount > 0 || !state.searchQuery.isEmpty {
                Text(state.matchCount > 0
                     ? "\(state.currentMatchIndex)/\(state.matchCount)"
                     : "0/0")
                    .font(.custom("HelveticaNeue", size: 13))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }

            // Previous match.
            Button { state.prevMatch() } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(state.matchCount > 0 ? Color.primary : Color.secondary)
            }
            .disabled(state.matchCount == 0)

            // Next match.
            Button { state.nextMatch() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(state.matchCount > 0 ? Color.primary : Color.secondary)
            }
            .disabled(state.matchCount == 0)

            // Done — close search and clear highlights.
            Button { withAnimation { state.closeSearch() } } label: {
                Text("Done")
                    .font(.custom("HelveticaNeue-Medium", size: 15))
                    .foregroundStyle(.primary)
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
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
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

    // MARK: - Floating Bar (keyboard not visible)

    private var floatingBar: some View {
        HStack(spacing: 24) {
            icon("mic")                { state.editor.textView?.becomeFirstResponder(); state.startRecording() }
            icon("camera")              { state.showCameraPicker = true }
            icon("photo.on.rectangle")  { state.showPhotoPicker = true }
            icon("paperclip")           { state.showFilePicker  = true }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .fixedSize()
        .background(Color.cardBackground)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
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
