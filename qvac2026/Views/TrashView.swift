//
//  TrashView.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 15/06/26.
//

import SwiftUI

struct TrashView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var trashed: [Note] = []
    @State private var showEmptyConfirm = false
    @State private var deleteTarget: Note?

    private let db = DatabaseService.shared.notes

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                headerBar
                content
            }
        }
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            db.purgeExpiredTrash()
            trashed = db.fetchTrashed()
        }
        .alert("Permanently delete all notes in Trash?", isPresented: $showEmptyConfirm) {
            Button("Delete All", role: .destructive) {
                db.emptyTrash()
                trashed = []
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Permanently delete this note?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let note = deleteTarget {
                    db.permanentlyDelete(id: note.id)
                    trashed = db.fetchTrashed()
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
            }
            Text("Trash")
                .font(.custom("HelveticaNeue-Bold", size: 16))
                .foregroundStyle(Color.labelPrimary)
            Spacer()
            Button("Empty") {
                showEmptyConfirm = true
            }
            .font(.custom("HelveticaNeue", size: 14))
            .foregroundStyle(trashed.isEmpty ? Color.labelSecondary : Color.red)
            .disabled(trashed.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if trashed.isEmpty {
            Spacer()
            Text("Trash is empty")
                .font(.custom("HelveticaNeue", size: 14))
                .foregroundStyle(Color.labelSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(trashed) { note in
                        noteRow(note)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func noteRow(_ note: Note) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.custom("HelveticaNeue-Medium", size: 14))
                    .foregroundStyle(Color.labelPrimary)
                    .lineLimit(1)
                Text(subtitleText(for: note))
                    .font(.custom("HelveticaNeue", size: 12))
                    .foregroundStyle(Color.labelSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 56)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteTarget = note
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                db.restoreFromTrash(id: note.id)
                trashed = db.fetchTrashed()
            } label: {
                Label("Restore", systemImage: "arrow.uturn.left")
            }
            .tint(.blue)
        }
    }

    private func subtitleText(for note: Note) -> String {
        guard let deletedAt = note.deletedAt else { return "" }
        let days = Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0
        let remaining = max(0, 30 - days)
        let deletedLabel = days == 0 ? "today" : days == 1 ? "1 day ago" : "\(days) days ago"
        return "Deleted \(deletedLabel) · auto-deletes in \(remaining) day\(remaining == 1 ? "" : "s")"
    }
}

#Preview {
    NavigationStack {
        TrashView()
    }
}
