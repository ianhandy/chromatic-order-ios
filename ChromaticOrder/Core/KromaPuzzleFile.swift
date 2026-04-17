//  Transferable wrapper around the creator's JSON export so the system
//  share sheet attaches a real file (with a .json extension) instead
//  of pasting a wall of text into the message body. Recipients get
//  something tappable — save to Files, preview inline in Mail, forward
//  as an attachment — instead of an unreadable text dump.

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct KromaPuzzleFile: Transferable {
    let json: String
    let difficulty: Int

    /// File name the system share sheet suggests when saving. Bracketed
    /// difficulty makes the file sortable when a player collects a
    /// bunch of shared puzzles.
    var suggestedFilename: String {
        "Kroma puzzle (\(difficulty) of 10).json"
    }

    static var transferRepresentation: some TransferRepresentation {
        // Export as UTType.json so Mail / Messages / Files / AirDrop
        // all recognize it and show a native file attachment row.
        // If we define a custom .kroma UTI later (Info.plist
        // UTExportedTypeDeclarations + associated app to open it),
        // swap this for .init(exportedContentType: .kromaPuzzle).
        DataRepresentation(exportedContentType: .json) { file in
            file.json.data(using: .utf8) ?? Data()
        }
        .suggestedFileName { $0.suggestedFilename }
    }
}
