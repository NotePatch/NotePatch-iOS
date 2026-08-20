import Combine
import Foundation

struct MarkdownBlock: Equatable, Identifiable, Sendable {
    let id: String
    let type: MarkdownBlockType
    let text: String
    let level: Int
    let inlineTokens: [MarkdownInlineToken]

    nonisolated init(id: String, type: MarkdownBlockType, text: String, level: Int = 0) {
        self.id = id
        self.type = type
        self.text = text
        self.level = level
        self.inlineTokens = parseMarkdownInline(text)
    }
}

enum MarkdownBlockType: Equatable, Sendable {
    case paragraph
    case heading
    case bullet
    case ordered
    case quote
    case code
}

struct MarkdownInlineToken: Equatable, Identifiable, Sendable {
    let id: String
    let text: String
    let type: MarkdownInlineType
}

enum MarkdownInlineType: Equatable, Sendable {
    case text
    case bold
    case code
    case link
}

nonisolated func parseMarkdownBlocks(_ markdown: String) -> [MarkdownBlock] {
    let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    var inCodeBlock = false
    var codeLines: [String] = []

    func appendBlock(_ type: MarkdownBlockType, _ text: String, level: Int = 0) {
        blocks.append(MarkdownBlock(id: "block-\(blocks.count)", type: type, text: text, level: level))
    }

    func flushParagraph() {
        if !paragraph.isEmpty {
            appendBlock(.paragraph, paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
            paragraph.removeAll()
        }
    }

    for rawLine in normalized.components(separatedBy: "\n") {
        let line = rawLine.trimmingTrailingSpacesAndTabs()
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            if inCodeBlock {
                appendBlock(.code, codeLines.joined(separator: "\n"))
                codeLines.removeAll()
                inCodeBlock = false
            } else {
                flushParagraph()
                inCodeBlock = true
            }
            continue
        }
        if inCodeBlock {
            codeLines.append(rawLine)
            continue
        }
        if trimmed.isEmpty {
            flushParagraph()
            continue
        }

        if let match = trimmed.firstMatch(pattern: "^(#{1,3})\\s+(.+)$") {
            flushParagraph()
            appendBlock(.heading, match[2].trimmingCharacters(in: .whitespaces), level: match[1].count)
            continue
        }

        if let match = trimmed.firstMatch(pattern: "^[-*+]\\s+(.+)$") {
            flushParagraph()
            appendBlock(.bullet, match[1].trimmingCharacters(in: .whitespaces))
            continue
        }

        if let match = trimmed.firstMatch(pattern: "^(\\d+)[.)]\\s+(.+)$") {
            flushParagraph()
            appendBlock(
                .ordered,
                match[2].trimmingCharacters(in: .whitespaces),
                level: Int(match[1]) ?? 1
            )
            continue
        }

        if trimmed.hasPrefix(">") {
            flushParagraph()
            appendBlock(.quote, String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            continue
        }

        paragraph.append(line)
    }

    if inCodeBlock {
        appendBlock(.code, codeLines.joined(separator: "\n"))
    }
    flushParagraph()
    return blocks
}

nonisolated func parseMarkdownInline(_ text: String) -> [MarkdownInlineToken] {
    var tokens: [MarkdownInlineToken] = []
    var index = text.startIndex

    func appendPlain(until end: String.Index) {
        if end > index {
            tokens.append(MarkdownInlineToken(id: "inline-\(tokens.count)", text: String(text[index..<end]), type: .text))
        }
    }

    while index < text.endIndex {
        let boldStart = text.range(of: "**", range: index..<text.endIndex)?.lowerBound
        let codeStart = text[index..<text.endIndex].firstIndex(of: "`")
        let linkStart = text[index..<text.endIndex].firstIndex(of: "[")
        let candidates = [boldStart, codeStart, linkStart].compactMap { $0 }
        guard let next = candidates.min() else {
            appendPlain(until: text.endIndex)
            break
        }
        appendPlain(until: next)
        index = next

        if boldStart == next {
            let contentStart = text.index(index, offsetBy: 2)
            if let end = text.range(of: "**", range: contentStart..<text.endIndex)?.lowerBound {
                tokens.append(MarkdownInlineToken(id: "inline-\(tokens.count)", text: String(text[contentStart..<end]), type: .bold))
                index = text.index(end, offsetBy: 2)
            } else {
                tokens.append(MarkdownInlineToken(id: "inline-\(tokens.count)", text: String(text[index..<text.endIndex]), type: .text))
                index = text.endIndex
            }
        } else if codeStart == next {
            let contentStart = text.index(after: index)
            if let end = text[contentStart..<text.endIndex].firstIndex(of: "`") {
                tokens.append(MarkdownInlineToken(id: "inline-\(tokens.count)", text: String(text[contentStart..<end]), type: .code))
                index = text.index(after: end)
            } else {
                tokens.append(MarkdownInlineToken(id: "inline-\(tokens.count)", text: String(text[index..<text.endIndex]), type: .text))
                index = text.endIndex
            }
        } else {
            guard
                let labelEndRange = text.range(of: "](", range: index..<text.endIndex),
                let urlEnd = text[labelEndRange.upperBound..<text.endIndex].firstIndex(of: ")")
            else {
                tokens.append(MarkdownInlineToken(id: "inline-\(tokens.count)", text: String(text[index]), type: .text))
                index = text.index(after: index)
                continue
            }
            let label = String(text[text.index(after: index)..<labelEndRange.lowerBound])
            let url = String(text[labelEndRange.upperBound..<urlEnd])
            tokens.append(MarkdownInlineToken(id: "inline-\(tokens.count)", text: url.isEmpty ? label : "\(label) (\(url))", type: .link))
            index = text.index(after: urlEnd)
        }
    }

    return tokens
}

@MainActor
private final class MarkdownBlockCacheBox: NSObject {
    let blocks: [MarkdownBlock]

    init(_ blocks: [MarkdownBlock]) {
        self.blocks = blocks
    }
}

@MainActor
private final class MarkdownInlineCacheBox: NSObject {
    let tokens: [MarkdownInlineToken]

    init(_ tokens: [MarkdownInlineToken]) {
        self.tokens = tokens
    }
}

@MainActor
private enum MarkdownRenderCache {
    static let blocks: NSCache<NSString, MarkdownBlockCacheBox> = {
        let cache = NSCache<NSString, MarkdownBlockCacheBox>()
        cache.countLimit = 24
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()
    static let inlineTokens: NSCache<NSString, MarkdownInlineCacheBox> = {
        let cache = NSCache<NSString, MarkdownInlineCacheBox>()
        cache.countLimit = 128
        cache.totalCostLimit = 512 * 1024
        return cache
    }()
}

@MainActor
func cachedMarkdownInlineTokens(_ text: String) -> [MarkdownInlineToken] {
    let key = text as NSString
    if let cached = MarkdownRenderCache.inlineTokens.object(forKey: key) {
        return cached.tokens
    }
    let tokens = parseMarkdownInline(text)
    MarkdownRenderCache.inlineTokens.setObject(
        MarkdownInlineCacheBox(tokens),
        forKey: key,
        cost: text.utf8.count
    )
    return tokens
}

@MainActor
func clearMarkdownRenderCache() {
    MarkdownRenderCache.blocks.removeAllObjects()
    MarkdownRenderCache.inlineTokens.removeAllObjects()
}

@MainActor
final class MarkdownRenderState: ObservableObject {
    @Published private(set) var blocks: [MarkdownBlock] = []
    private var markdown = ""
    private var parseTask: Task<Void, Never>?

    deinit {
        parseTask?.cancel()
    }

    func load(_ markdown: String) {
        guard self.markdown != markdown else { return }
        self.markdown = markdown
        parseTask?.cancel()
        let key = markdown as NSString
        if let cached = MarkdownRenderCache.blocks.object(forKey: key) {
            blocks = cached.blocks
            return
        }

        if markdown.utf8.count < 4_096 {
            let parsed = parseMarkdownBlocks(markdown)
            cache(parsed, for: key, source: markdown)
            blocks = parsed
            return
        }

        blocks = []
        let expectedMarkdown = markdown
        parseTask = Task { [weak self] in
            let trace = NPPerformanceTrace.begin("MarkdownParse")
            let parsed = await Task.detached(priority: .userInitiated) {
                parseMarkdownBlocks(expectedMarkdown)
            }.value
            NPPerformanceTrace.end("MarkdownParse", id: trace)
            guard !Task.isCancelled, let self, self.markdown == expectedMarkdown else { return }
            self.cache(parsed, for: key, source: expectedMarkdown)
            self.blocks = parsed
        }
    }

    private func cache(_ blocks: [MarkdownBlock], for key: NSString, source: String) {
        MarkdownRenderCache.blocks.setObject(
            MarkdownBlockCacheBox(blocks),
            forKey: key,
            cost: source.utf8.count
        )
    }
}

private extension String {
    nonisolated func trimmingTrailingSpacesAndTabs() -> String {
        var result = self
        while let last = result.last, last == " " || last == "\t" {
            result.removeLast()
        }
        return result
    }
}

private extension String {
    nonisolated func firstMatch(pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else {
            return nil
        }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: self) else {
                return nil
            }
            return String(self[range])
        }
    }
}
