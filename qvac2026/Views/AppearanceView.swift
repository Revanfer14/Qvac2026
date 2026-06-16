//
//  AppearanceView.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 15/06/26.
//

import SwiftUI

struct AppearanceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                headerBar
                rowList
                Spacer()
            }
        }
        .background(AppBackground())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
            }
            Text("Appearance")
                .font(.custom("HelveticaNeue-Bold", size: 16))
                .foregroundStyle(Color.labelPrimary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var rowList: some View {
        VStack(spacing: 0) {
            ForEach(Appearance.allCases) { option in
                Button {
                    theme.set(option)
                } label: {
                    HStack(spacing: 12) {
                        Text(option.label)
                            .font(.custom("HelveticaNeue-Medium", size: 14))
                            .foregroundStyle(Color.labelPrimary)
                        Spacer()
                        if theme.appearance == option {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.labelPrimary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceView()
            .environmentObject(ThemeStore.shared)
    }
}
