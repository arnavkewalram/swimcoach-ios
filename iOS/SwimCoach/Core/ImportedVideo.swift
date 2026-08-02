import SwiftUI
import CoreTransferable

/// Copies the picked video into tmp so the analysis pipeline gets a
/// stable file URL that outlives the picker's security scope.
struct ImportedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("import-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return ImportedVideo(url: dest)
        }
    }
}

