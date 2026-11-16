import Foundation
import AVFoundation
import CryptoKit

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
    // Optional for backwards-compatible decoding of existing libraries.
    var listeningSessions: [ListeningSession]? = nil
}

struct ListeningSession: Codable, Hashable, Identifiable {
    var id = UUID()
    let startedAt: Date
    var blocks: [Int: Date] = [:]
}

extension Book {
    mutating func recordListening(block: Int, sessionID: UUID, at date: Date) {
        guard blocks.indices.contains(block) else { return }
        var sessions = listeningSessions ?? []
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            // Keep the start time, rather than replacing it on pause/resume.
            if sessions[index].blocks[block] == nil { sessions[index].blocks[block] = date }
        } else {
            sessions.append(ListeningSession(id: sessionID, startedAt: date, blocks: [block: date]))
        }
        listeningSessions = Array(sessions.suffix(30))
    }

    func lastListenedAt(block: Int, sessionID: UUID? = nil) -> Date? {
        (listeningSessions ?? []).reversed()
            .first { (sessionID == nil || $0.id == sessionID) && $0.blocks[block] != nil }?.blocks[block]
    }
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

struct ReaderVoice: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String
    var id: String { rawValue }
    var cacheKey: String { SHA256.hash(data: Data(rawValue.utf8)).map { String(format: "%02x", $0) }.joined() }
    var systemVoice: AVSpeechSynthesisVoice? {
        guard rawValue.hasPrefix("com.apple.") else { return nil }
        return AVSpeechSynthesisVoice(identifier: rawValue)
    }
    var title: String {
        guard let voice = systemVoice else { return String(localized: "voice.unavailable") }
        let language = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
        let quality: String
        switch voice.quality {
        case .premium: quality = " · " + String(localized: "voice.premium")
        case .enhanced: quality = " · " + String(localized: "voice.enhanced")
        default: quality = ""
        }
        return "\(voice.name) · \(language)\(quality)"
    }
    static var available: [ReaderVoice] {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--no-system-voices") { return [] }
        #endif
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.identifier.hasPrefix("com.apple.") && !$0.voiceTraits.contains(.isPersonalVoice) && ($0.language.hasPrefix("es-") || $0.language.hasPrefix("en-")) }
            .sorted {
                if $0.language != $1.language { return $0.language > $1.language }
                if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            .map { ReaderVoice(rawValue: $0.identifier) }
    }
    static var spanish: ReaderVoice { preferred(language: "es-ES") }
    static var english: ReaderVoice { preferred(language: "en-US") }
    private static func preferred(language: String) -> ReaderVoice {
        ReaderVoice(rawValue: AVSpeechSynthesisVoice(language: language)?.identifier ?? "unavailable-\(language)")
    }
}
