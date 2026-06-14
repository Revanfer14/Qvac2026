//
//  SearchBar.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 14/06/26.
//

import SwiftUI

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(Color.secondary)

            TextField("Search here", text: $text)
                .font(.custom("HelveticaNeue", size: 16))
                .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
        )
    }
}

#Preview {
    SearchBar(text: .constant(""))
        .padding()
}
