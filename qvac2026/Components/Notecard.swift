//
//  Notecard.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 14/06/26.
//

import SwiftUI

struct NoteCard: View {
    let note: Note

    var body: some View {
        HStack(spacing: 14) {
            NoteIcon(type: note.type)
            noteContent
            Spacer(minLength: 8)
            moreButton
        }
        .padding(16)
        .background(cardBackground)
    }

    private var noteContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.title)
                .font(.custom("HelveticaNeue-Bold", size: 15))
                .foregroundStyle(Color.primary)
                .lineLimit(1)

            Text(note.preview)
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)

            Text(note.timeAgo)
                .font(.custom("HelveticaNeue", size: 12))
                .foregroundStyle(Color(UIColor.tertiaryLabel))
        }
    }

    private var moreButton: some View {
        Button(action: {}) {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.secondary)
                .rotationEffect(.degrees(90))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.white)
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
}

struct NoteIcon: View {
    let type: NoteType

    private var symbolName: String {
        switch type {
        case .text:   return "doc.text.fill"
        case .audio:  return "waveform"
        case .folder: return "folder.fill"
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "D6E8FF"))
                .frame(width: 58, height: 58)

            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "5EA0F0"), Color(hex: "1E5DE0")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

#Preview {
    VStack(spacing: 10) {
        NoteCard(note: Note.samples[0])
        NoteCard(note: Note.samples[2])
    }
    .padding()
    .background(Color(hex: "F1F9FF"))
}
