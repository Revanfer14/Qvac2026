//
//  qvac2026App.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 14/06/26.
//

import SwiftUI

@main
struct qvac2026App: App {
    @StateObject private var theme = ThemeStore.shared

    init() {
        _ = DatabaseService.shared
        DatabaseService.shared.notes.purgeExpiredTrash()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(theme.appearance.colorScheme)
                .environmentObject(theme)
        }
    }
}
