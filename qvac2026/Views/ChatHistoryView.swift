//
//  ChatHistoryView.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 14/06/26.
//

import SwiftUI

struct ChatHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [ChatSession] = []

    var body: some View {
        ZStack {
            AppBackground()

            VStack(alignment: .leading, spacing: 0) {
                // Nav bar
                HStack(spacing: 8) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.primary)
                    }
                    .padding(.trailing, 10)

                    Text("Chat History")
                        .font(.custom("HelveticaNeue-Medium", size: 16))
                        .foregroundStyle(Color.labelPrimary)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .padding(.bottom, 10)

                if sessions.isEmpty {
                    Spacer()
                    Text("No chat history yet")
                        .font(.custom("HelveticaNeue", size: 14))
                        .foregroundStyle(Color.labelTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                } else {
                    // Section label
                    Text("RECENT")
                        .font(.custom("HelveticaNeue-Medium", size: 14))
                        .foregroundStyle(Color.labelSecondary)
                        .kerning(1.0)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)

                    // Chat list
                    VStack(spacing: 20) {
                        ForEach(sessions) { session in
                            ChatHistoryRow(title: session.title)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            sessions = DatabaseService.shared.chats.fetchSessions()
        }
    }
}

struct ChatHistoryRow: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.custom("HelveticaNeue-Medium", size: 14))
                .foregroundStyle(Color.labelPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: {}) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .rotationEffect(.degrees(90))
            }
            .buttonStyle(.plain)
        }
        .frame(height: 20)
    }
}

#Preview {
    NavigationStack {
        ChatHistoryView()
    }
}
