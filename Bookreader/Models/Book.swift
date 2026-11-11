import Foundation

struct ReadingBlock: Codable, Hashable, Identifiable {
    var id: Int
    var heading: String
    var text: String
    var chapterID: Int? = nil
}

struct Book: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var format: String
    var blocks: [ReadingBlock]
    var position = 0
    var importedAt = Date()
}

struct ReadingChapter: Identifiable, Hashable {
    let id: Int
    let title: String
    let start: Int
    var end: Int // Exclusive block index.
    var range: Range<Int> { start..<end }
}

extension Book {
    var chapters: [ReadingChapter] {
        var result: [ReadingChapter] = []
        for (index, block) in blocks.enumerated() {
            // Older libraries have no chapter ID: retain consecutive heading groups.
            let startsChapter = index == 0 || (block.chapterID != nil
                ? block.chapterID != blocks[index - 1].chapterID
                : block.heading != blocks[index - 1].heading)
            if startsChapter {
                result.append(ReadingChapter(id: result.count, title: block.heading, start: index, end: index + 1))
            } else {
                result[result.count - 1].end = index + 1
            }
        }
        return result
    }
}

enum ReaderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum ReaderVoice: String, Codable, CaseIterable, Identifiable {
    case dora = "ef_dora", alex = "em_alex", santa = "em_santa", heart = "af_heart"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dora: return String(localized: "voice.dora")
        case .alex: return String(localized: "voice.alex")
        case .santa: return String(localized: "voice.santa")
        case .heart: return String(localized: "voice.heart")
        }
    }
    var isSpanish: Bool { self != .heart }
}
