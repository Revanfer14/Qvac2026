//
//  HomeView.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 14/06/26.
//

import SwiftUI

struct HomeView: View {
    
    @State private var searchText: String = ""
    @State private var allNotes: [Note] = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                titleHeader
                SearchBar(text: $searchText)
                
                ForEach(groupedNotes, id: \.title) { group in
                    NoteSectionView(title: group.title, notes: group.notes)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            allNotes = DatabaseService.shared.notes.fetchActive()
        }
    }
    
    private var titleHeader: some View {
        HStack(alignment: .center) {
            Text("Notes")
                .font(.custom("HelveticaNeue-Bold", size: 34))
                .foregroundStyle(Color.primary)
            
            Spacer()
            
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.primary)
            }
        }
    }
    
    private var groupedNotes: [NoteGroup] {
        let calendar = Calendar.current
        
        let source = searchText.isEmpty
        ? allNotes
        : allNotes.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        
        let today = source.filter { calendar.isDateInToday($0.createdAt) }
        
        let yesterday = source.filter { calendar.isDateInYesterday($0.createdAt) }
        
        let previousWeek = source.filter {
            let isRecent = calendar.isDateInToday($0.createdAt)
            || calendar.isDateInYesterday($0.createdAt)
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now)!
            return !isRecent && $0.createdAt >= weekAgo
        }
        
        return [
            NoteGroup(title: "TODAY",         notes: today),
            NoteGroup(title: "YESTERDAY",     notes: yesterday),
            NoteGroup(title: "PREVIOUS WEEK", notes: previousWeek)
        ]
            .filter { !$0.notes.isEmpty }
    }
}

struct NoteGroup {
    let title: String
    let notes: [Note]
}

struct NoteSectionView: View {
    let title: String
    let notes: [Note]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.custom("HelveticaNeue", size: 13))
                .foregroundStyle(Color.secondary)
                .kerning(1.0)
            
            VStack(spacing: 10) {
                ForEach(notes) { note in
                    NoteCard(note: note)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
