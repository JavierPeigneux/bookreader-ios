import Foundation
import PDFKit
import SwiftSoup
import ZIPFoundation

struct DocumentImporter {
    static let maxBytes = 25 * 1024 * 1024
    static let maxCharacters = 2_000_000

    func read(_ url: URL) throws -> Book {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Self.maxBytes else { throw ReaderError.message(String(localized: "error.document.byte_limit")) }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maxBytes else { throw ReaderError.message(String(localized: "error.document.byte_limit")) }
        let ext = url.pathExtension.lowercased()
        let sections: [(String, String)]
        switch ext {
        case "txt":
            sections = [(String(localized: "document.heading.text"), try decode(data))]
        case "md", "markdown":
            let source = try decode(data)
            // Preserve paragraph boundaries while removing Markdown presentation.
            let plain = source.components(separatedBy: "\n").map { line in
                let stripped = line.replacingOccurrences(of: #"^\s{0,3}(#{1,6}\s+|>\s?|[-*+]\s+|\d+\.\s+)"#, with: "", options: .regularExpression)
                if stripped.trimmingCharacters(in: .whitespaces).hasPrefix("```") { return "" }
                return (try? AttributedString(markdown: stripped)).map { String($0.characters) } ?? stripped
            }.joined(separator: "\n")
            sections = [(String(localized: "document.heading.text"), plain)]
        case "pdf":
            guard let pdf = PDFDocument(data: data), !pdf.isLocked else {
                throw ReaderError.message(String(localized: "error.pdf.open"))
            }
            let chapterStarts = Self.pdfChapterStarts(pdf)
            var pages: [(String, String)] = []
            for index in 0..<pdf.pageCount {
                let text = pdf.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else {
                    throw ReaderError.message(String.localizedStringWithFormat(String(localized: "error.pdf.ocr_required"), Int64(index + 1)))
                }
                let heading = chapterStarts.last(where: { $0.0 <= index })?.1
                    ?? String.localizedStringWithFormat(String(localized: "document.heading.page"), Int64(index + 1))
                if let last = pages.last, !chapterStarts.isEmpty, last.0 == heading,
                   !chapterStarts.contains(where: { $0.0 == index }) {
                    pages[pages.count - 1].1 += "\n\n" + text
                } else { pages.append((heading, text)) }
            }
            sections = pages
        case "epub": sections = try epub(data)
        default: throw ReaderError.message(String(localized: "error.document.unsupported_format"))
        }
        guard sections.reduce(0, { $0 + $1.1.count }) <= Self.maxCharacters else {
            throw ReaderError.message(String(localized: "error.document.character_limit"))
        }
        let blocks = sections.enumerated().flatMap { chapter, section in
            Self.split(section.1).map { (chapter, section.0, $0) }
        }.enumerated().map { ReadingBlock(id: $0.offset, heading: $0.element.1, text: $0.element.2, chapterID: $0.element.0) }
        guard !blocks.isEmpty else { throw ReaderError.message(String(localized: "error.document.empty")) }
        return Book(title: url.deletingPathExtension().lastPathComponent, format: ext.uppercased(), blocks: blocks)
    }

    /// Top-level usable outline entries define chapters; nested entries are used
    /// when a container has no destination. Page-level boundaries avoid lost text.
    static func pdfChapterStarts(_ pdf: PDFDocument) -> [(Int, String)] {
        var entries: [(Int, String)] = []
        func visit(_ outline: PDFOutline) {
            let destination = outline.destination ?? (outline.action as? PDFActionGoTo)?.destination
            if let page = destination?.page, let title = outline.label, !title.isEmpty {
                let index = pdf.index(for: page)
                if index != NSNotFound { entries.append((index, title)); return }
            }
            for index in 0..<outline.numberOfChildren {
                if let child = outline.child(at: index) { visit(child) }
            }
        }
        if let root = pdf.outlineRoot {
            for index in 0..<root.numberOfChildren {
                if let child = root.child(at: index) { visit(child) }
            }
        }
        var seen = Set<Int>()
        return entries.sorted { $0.0 < $1.0 }.filter { seen.insert($0.0).inserted }
    }

    private func decode(_ data: Data) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ReaderError.message(String(localized: "error.document.encoding"))
        }
        return text.replacingOccurrences(of: "\u{feff}", with: "")
    }

    static func split(_ text: String, limit: Int = 350) -> [String] {
        var remaining = text.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [String] = []
        while !remaining.isEmpty {
            var end = remaining.index(remaining.startIndex, offsetBy: min(limit, remaining.count))
            if end < remaining.endIndex {
                let prefix = remaining[..<end]
                if let boundary = prefix.lastIndex(where: { ".!?\n".contains($0) }), prefix.distance(from: prefix.startIndex, to: boundary) > limit / 3 {
                    end = remaining.index(after: boundary)
                } else if let space = prefix.lastIndex(where: { $0.isWhitespace }) {
                    end = remaining.index(after: space)
                }
            }
            let part = String(remaining[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty { result.append(part) }
            remaining = String(remaining[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    static func epubSections(_ document: Document, fallback: String) throws -> [(String, String)] {
        let body = document.body() ?? document
        // Prefer the highest heading level present to avoid treating every
        // subsection as a chapter. Spine order remains authoritative.
        let headingTag = try body.select("h1").isEmpty() ? "h2" : "h1"
        var sections: [(String, String)] = []
        var title = fallback
        var text = ""
        func flush() {
            let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty { sections.append((title, content)) }
            text = ""
        }
        func visit(_ node: Node) throws {
            if let element = node as? Element {
                if element.tagName() == headingTag {
                    flush()
                    title = try element.text()
                    text = title + "\n\n"
                    return
                }
                for child in element.getChildNodes() { try visit(child) }
                if ["p", "div", "section", "br", "li", "h1", "h2", "h3"].contains(element.tagName()) { text += "\n" }
            } else if let node = node as? TextNode {
                text += node.getWholeText()
            }
        }
        try visit(body)
        flush()
        return sections
    }

    private func epub(_ data: Data) throws -> [(String, String)] {
        let archive = try Archive(data: data, accessMode: .read)
        var expanded: UInt64 = 0
        for entry in archive {
            expanded += UInt64(entry.uncompressedSize)
            guard expanded <= 100_000_000 else { throw ReaderError.message(String(localized: "error.epub.expanded_limit")) }
        }
        func readEntry(_ path: String) throws -> Data {
            guard let entry = archive[path], entry.type == .file else {
                throw ReaderError.message(String.localizedStringWithFormat(String(localized: "error.epub.entry_missing"), path))
            }
            var result = Data()
            _ = try archive.extract(entry) { chunk in
                guard result.count + chunk.count <= 100_000_000 else { throw ReaderError.message(String(localized: "error.epub.entry_limit")) }
                result.append(chunk)
            }
            return result
        }
        if archive["META-INF/encryption.xml"] != nil {
            let encryption = try XMLIndex(data: readEntry("META-INF/encryption.xml"))
            let allowed = ["http://www.idpf.org/2008/embedding", "http://ns.adobe.com/pdf/enc#RC"]
            guard !encryption.algorithms.isEmpty, encryption.algorithms.allSatisfy(allowed.contains) else {
                throw ReaderError.message(String(localized: "error.epub.drm"))
            }
        }
        let container = try XMLIndex(data: readEntry("META-INF/container.xml"))
        guard let packagePath = container.rootPath else { throw ReaderError.message(String(localized: "error.epub.index_missing")) }
        let package = try XMLIndex(data: readEntry(packagePath))
        let base = URL(fileURLWithPath: "/" + packagePath).deletingLastPathComponent()
        var sections: [(String, String)] = []
        for id in package.spine {
            guard let href = package.manifest[id] else { throw ReaderError.message(String(localized: "error.epub.chapter_missing")) }
            guard let resolved = URL(string: href, relativeTo: base.appendingPathComponent("")), resolved.scheme == "file" else {
                throw ReaderError.message(String(localized: "error.epub.chapter_reference"))
            }
            let path = resolved.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let html = try decode(readEntry(path))
            let document = try SwiftSoup.parse(html)
            try document.select("script, style, nav").remove()
            let fallback = try document.select("title").first()?.text() ?? String.localizedStringWithFormat(String(localized: "document.heading.chapter"), Int64(sections.count + 1))
            sections.append(contentsOf: try Self.epubSections(document, fallback: fallback))
        }
        return sections
    }
}

private final class XMLIndex: NSObject, XMLParserDelegate {
    var rootPath: String?
    var manifest: [String: String] = [:]
    var spine: [String] = []
    var algorithms: [String] = []
    init(data: Data) throws {
        super.init()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        guard parser.parse() else { throw ReaderError.message(String(localized: "error.epub.xml_invalid")) }
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        switch elementName.split(separator: ":").last.map(String.init) ?? elementName {
        case "rootfile": if rootPath == nil { rootPath = attributes["full-path"] }
        case "item": if let id = attributes["id"], let href = attributes["href"] { manifest[id] = href }
        case "itemref": if attributes["linear"] != "no", let id = attributes["idref"] { spine.append(id) }
        case "EncryptionMethod": algorithms.append(attributes["Algorithm"] ?? "")
        default: break
        }
    }
}
