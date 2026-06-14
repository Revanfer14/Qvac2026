//
//  Note.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 14/06/26.
//

import Foundation

enum NoteType {
    case text
    case audio
    case folder
}

struct Note: Identifiable {
    let id: UUID = UUID()
    var title: String
    var preview: String
    var createdAt: Date
    var type: NoteType

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: .now)
    }
}

extension Note {
    static var samples: [Note] {
        let calendar = Calendar.current
        let now = Date()

        func date(hoursAgo hours: Int, daysAgo days: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: -days, to: now)!
            return calendar.date(byAdding: .hour, value: -hours, to: base)!
        }

        return [
            // Today
            Note(title: "Coffee shop recommendation in G...",
                 preview: "Try the new café near the office. Sandy ...",
                 createdAt: date(hoursAgo: 1),
                 type: .text),

            Note(title: "Final test to do list",
                 preview: "Items to complete before the demo day ...",
                 createdAt: date(hoursAgo: 2),
                 type: .text),

            // Yesterday
            Note(title: "Interview with user",
                 preview: "Key insights from the research session ...",
                 createdAt: date(hoursAgo: 2, daysAgo: 1),
                 type: .audio),

            Note(title: "Coffee shop recommendation in G...",
                 preview: "Try the new café near the office. Sandy ...",
                 createdAt: date(hoursAgo: 4, daysAgo: 1),
                 type: .text),

            Note(title: "Coffee shop recommendation in G...",
                 preview: "Try the new café near the office. Sandy ...",
                 createdAt: date(hoursAgo: 6, daysAgo: 1),
                 type: .text),

            // Previous Week
            Note(title: "Weekly project review",
                 preview: "QVAC hackathon progress and next steps ...",
                 createdAt: date(hoursAgo: 0, daysAgo: 4),
                 type: .folder)
        ]
    }
}
