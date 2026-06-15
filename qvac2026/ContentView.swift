//
//  ContentView.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 14/06/26.
//

import SwiftUI

struct ContentView: View {

    @State private var selectedTab   = 0
    @State private var showNewNote   = false
    @State private var refreshTick   = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(refreshTick: refreshTick)
                    .navigationDestination(isPresented: $showNewNote) {
                        NoteDetailView()
                    }
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(0)

            Color.clear
                .tabItem { Label("New", systemImage: "plus") }
                .tag(1)

            NavigationStack {
                ChatAIView()
            }
            .tabItem { Label("ChatAI", systemImage: "sparkles") }
            .tag(2)
        }
        .onChange(of: selectedTab) { _, new in
            if new == 1 {
                showNewNote = true
                selectedTab = 0
            }
        }
        .onChange(of: showNewNote) { _, isShowing in
            if !isShowing { refreshTick += 1 }
        }
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .bgTop,    location: 0.00),
                .init(color: .bgMid,    location: 0.42),
                .init(color: .bgBottom, location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension Color {
    static let labelPrimary   = Color("Colors/LabelPrimary")
    static let labelSecondary = Color("Colors/LabelSecondary")
    static let labelTertiary  = Color("Colors/LabelTertiary")
    static let bgTop          = Color("Colors/BgTop")
    static let bgMid          = Color("Colors/BgMid")
    static let bgBottom       = Color("Colors/BgBottom")
    static let cardBackground = Color("Colors/CardBackground")
    static let iconBackground = Color("Colors/IconBackground")
    static let bluePrimary    = Color("Colors/BluePrimary")
    static let blueLight      = Color("Colors/BlueLight")
    static let blueMedium     = Color("Colors/BlueMedium")
    static let blueBold       = Color("Colors/BlueBold")
    static let blueBorder     = Color("Colors/BlueBorder")

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
