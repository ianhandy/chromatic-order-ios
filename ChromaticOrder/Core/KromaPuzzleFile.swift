//  Transferable wrapper around the creator's JSON export so the system
//  share sheet attaches a real file instead of pasting a wall of text.
//  Files use the custom .kroma extension + com.ianhandy.kroma.puzzle
//  UTI (declared in Info.plist's UTExportedTypeDeclarations). Apps
//  that can read JSON still see it as text; Kroma itself is the
//  registered handler so tapping a .kroma file in Mail / Files /
//  AirDrop offers "Open in Kroma" and routes the URL through
//  ChromaticOrderApp's .onOpenURL handler.

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Custom type for shared Kroma puzzles. Conforms to JSON so any
    /// JSON reader can still open the file as text, but the UTI
    /// itself is unique to Kroma so the system pairs .kroma files
    /// with this app.
    static let kromaPuzzle = UTType(
        exportedAs: "com.ianhandy.kroma.puzzle",
        conformingTo: .json
    )
}

struct KromaPuzzleFile: Transferable {
    let json: String
    let difficulty: Int

    /// File name the system share sheet suggests when saving. The
    /// difficulty in the name helps when a player's collected several
    /// shared puzzles — sortable, legible at a glance.
    var suggestedFilename: String {
        "Kromatika puzzle (\(difficulty) of 10).kroma"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .kromaPuzzle) { file in
            file.json.data(using: .utf8) ?? Data()
        }
        .suggestedFileName { $0.suggestedFilename }
    }
}
