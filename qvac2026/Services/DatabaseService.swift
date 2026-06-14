//
//  DatabaseService.swift
//  qvac2026
//
//  Created by Revan Ferdinand on 14/06/26.
//

import Foundation
import SQLite

class DatabaseService {

    static let shared = DatabaseService()

    private var db: Connection?

    // Table & Columns

    private let notesTable = Table("notes")

    private let colId        = Expression<String>("id")
    private let colTitle     = Expression<String>("title")
    private let colPreview   = Expression<String>("preview")
    private let colCreatedAt = Expression<Double>("created_at")
    private let colType      = Expression<String>("type")

    private init() {
        setupDatabase()
    }

    private func setupDatabase() {
        do {
            let path = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("qvac.sqlite3")
                .path

            db = try Connection(path)
            try createTableIfNeeded()

        } catch {
            print("Database setup error: \(error)")
        }
    }

    private func createTableIfNeeded() throws {
        try db?.run(notesTable.create(ifNotExists: true) { t in
            t.column(colId,        primaryKey: true)
            t.column(colTitle)
            t.column(colPreview)
            t.column(colCreatedAt)
            t.column(colType)
        })
    }


    func insertNote(_ note: Note) {
        do {
            let insert = notesTable.insert(
                colId        <- note.id.uuidString,
                colTitle     <- note.title,
                colPreview   <- note.preview,
                colCreatedAt <- note.createdAt.timeIntervalSince1970,
                colType      <- note.type.rawValue
            )
            try db?.run(insert)

        } catch {
            print("Insert error: \(error)")
        }
    }

    func fetchAllNotes() -> [Note] {
        var notes: [Note] = []

        do {
            guard let rows = try db?.prepare(notesTable.order(colCreatedAt.desc)) else { return [] }

            for row in rows {
                let note = Note(
                    id:        UUID(uuidString: row[colId]) ?? UUID(),
                    title:     row[colTitle],
                    preview:   row[colPreview],
                    createdAt: Date(timeIntervalSince1970: row[colCreatedAt]),
                    type:      NoteType(rawValue: row[colType]) ?? .text
                )
                notes.append(note)
            }

        } catch {
            print("Fetch error: \(error)")
        }

        return notes
    }

    func updateNote(_ note: Note) {
        let target = notesTable.filter(colId == note.id.uuidString)

        do {
            try db?.run(target.update(
                colTitle   <- note.title,
                colPreview <- note.preview,
                colType    <- note.type.rawValue
            ))
        } catch {
            print("Update error: \(error)")
        }
    }


    func deleteNote(_ note: Note) {
        let target = notesTable.filter(colId == note.id.uuidString)

        do {
            try db?.run(target.delete())
        } catch {
            print("Delete error: \(error)")
        }
    }
}
