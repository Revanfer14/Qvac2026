//
//  ChatAIView.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 14/06/26.
//

import SwiftUI

struct ChatAIView: View {
    
    @State private var inputText: String = ""
    
    private let suggestions = [
        "What is my to do list for 3 days ahead",
        "Give me and overview of my last 14 days",
        "Summarize my notes from the pas 3 days"
    ]
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Entropy AI")
                        .font(.custom("HelveticaNeue-Bold", size: 34))
                        .foregroundStyle(Color.primary)
                    
                    Spacer()
                    
                    NavigationLink(destination: ChatHistoryView()) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Spacer()
                
                VStack(spacing: 12) {
                    Text("Ask about your note")
                        .font(.custom("HelveticaNeue-Medium", size: 20))
                        .foregroundStyle(Color.labelPrimary)
                        .padding(.bottom, 4)
                    
                    ForEach(suggestions, id: \.self) { suggestion in
                        SuggestionPill(text: suggestion)
                    }
                }
                
                Spacer()
                
                ChatInputBar(text: $inputText)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct SuggestionPill: View {
    let text: String
    
    var body: some View {
        Button(action: {}) {
            HStack {
                Text(text)
                    .font(.custom("HelveticaNeue-Medium", size: 14))
                    .foregroundStyle(Color.blueMedium)
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.blueMedium)
            }
            
        }
        .buttonStyle(.plain)
        .frame(width: 303, height: 40)
        .padding(.horizontal, 15)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.cardBackground)
        )
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 4,
            x: 0,                             
            y: 4
        )
    }
}

struct ChatInputBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: {}) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 44, height: 48)
            }
            
            TextField("Ask Entropy anything", text: $text)
                .font(.custom("HelveticaNeue", size: 14))
                .foregroundStyle(Color.primary)
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "microphone")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 44, height: 48)
            }
        }
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color("Colors/CardBackground"))
        )
    }
}

#Preview {
    NavigationStack {
        ChatAIView()
    }
}

#Preview("Input Bar") {
    ChatInputBar(text: .constant(""))
        .padding()
}
