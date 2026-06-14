//
//  ContentView.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 14/06/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack {
                NoteDetailView()
            }
            .tabItem {
                Label("New", systemImage: "plus")
            }

            NavigationStack {
                ChatAIView()
            }
            .tabItem {
                Label("ChatAI", systemImage: "sparkles")
            }
        }
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "FFFFFF"), location: 0.00),
                .init(color: Color(hex: "F1F9FF"), location: 0.42),
                .init(color: Color(hex: "E4F4FF"), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double(int >> 16) / 255
        let g = Double(int >> 8 & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    ContentView()
}
