//
//  ChatHistoryViewModel.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 17/06/26.
//

import Foundation
import Combine

@MainActor
final class ChatHistoryViewModel: ObservableObject {

    @Published var sessions: [ChatSession] = []

    func load() {
        sessions = DatabaseService.shared.chats.fetchSessions()
    }
}
