import Foundation
import SwiftData

@Model
final class LyricsLine {
    var index: Int
    var text: String
    var timestampSeconds: Double?
    var section: String?

    init(
        index: Int,
        text: String,
        timestampSeconds: Double? = nil,
        section: String? = nil
    ) {
        self.index = index
        self.text = text
        self.timestampSeconds = timestampSeconds
        self.section = section
    }
}
