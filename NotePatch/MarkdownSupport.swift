import Foundation

struct MarkdownBlock: Equatable, Identifiable {
    let id = UUID()
    let type: MarkdownBlockType
    let text: String
    let level: Int

    init(type: MarkdownBlockType, text: String, level: Int = 0) {
        self.type = type
        self.text = text
        self.level = level
    }
}

enum MarkdownBlockType: Equatable {
    case paragraph
    case heading
    case bullet
    case ordered
    case quote
    case code
}

struct MarkdownInlineToken: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let type: MarkdownInlineType
}

enum MarkdownInlineType: Equatable {
    case text
    case bold
    case code
    case link
}

func parseMarkdownBlocks(_ markdown: String) -> [MarkdownBlock] {
    let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    var blocks: [MarkdownBlock] = []
    var paragraph: [String] = []
    var inCodeBlock = false
    var codeLines: [String] = []

    func flushParagraph() {
        if !paragraph.isEmpty {
            blocks.append(MarkdownBlock(type: .paragraph, text: paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            paragraph.removeAll()
        }
    }

    for rawLine in normalized.components(separatedBy: "\n") {
        let line = rawLine.trimmingTrailingSpacesAndTabs()
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            if inCodeBlock {
                blocks.append(MarkdownBlock(type: .code, text: codeLines.joined(separator: "\n")))
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
            blocks.append(MarkdownBlock(type: .heading, text: match[2].trimmingCharacters(in: .whitespaces), level: match[1].count))
            continue
        }

        if let match = trimmed.firstMatch(pattern: "^[-*+]\\s+(.+)$") {
            flushParagraph()
            blocks.append(MarkdownBlock(type: .bullet, text: match[1].trimmingCharacters(in: .whitespaces)))
            continue
        }

        if let match = trimmed.firstMatch(pattern: "^\\d+[.)]\\s+(.+)$") {
            flushParagraph()
            blocks.append(MarkdownBlock(type: .ordered, text: match[1].trimmingCharacters(in: .whitespaces)))
            continue
        }

        if trimmed.hasPrefix(">") {
            flushParagraph()
            blocks.append(MarkdownBlock(type: .quote, text: String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
            continue
        }

        paragraph.append(line)
    }

    if inCodeBlock {
        blocks.append(MarkdownBlock(type: .code, text: codeLines.joined(separator: "\n")))
    }
    flushParagraph()
    return blocks
}

func parseMarkdownInline(_ text: String) -> [MarkdownInlineToken] {
    var tokens: [MarkdownInlineToken] = []
    var index = text.startIndex

    func appendPlain(until end: String.Index) {
        if end > index {
            tokens.append(MarkdownInlineToken(text: String(text[index..<end]), type: .text))
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
                tokens.append(MarkdownInlineToken(text: String(text[contentStart..<end]), type: .bold))
                index = text.index(end, offsetBy: 2)
            } else {
                tokens.append(MarkdownInlineToken(text: String(text[index..<text.endIndex]), type: .text))
                index = text.endIndex
            }
        } else if codeStart == next {
            let contentStart = text.index(after: index)
            if let end = text[contentStart..<text.endIndex].firstIndex(of: "`") {
                tokens.append(MarkdownInlineToken(text: String(text[contentStart..<end]), type: .code))
                index = text.index(after: end)
            } else {
                tokens.append(MarkdownInlineToken(text: String(text[index..<text.endIndex]), type: .text))
                index = text.endIndex
            }
        } else {
            guard
                let labelEndRange = text.range(of: "](", range: index..<text.endIndex),
                let urlEnd = text[labelEndRange.upperBound..<text.endIndex].firstIndex(of: ")")
            else {
                tokens.append(MarkdownInlineToken(text: String(text[index]), type: .text))
                index = text.index(after: index)
                continue
            }
            let label = String(text[text.index(after: index)..<labelEndRange.lowerBound])
            let url = String(text[labelEndRange.upperBound..<urlEnd])
            tokens.append(MarkdownInlineToken(text: url.isEmpty ? label : "\(label) (\(url))", type: .link))
            index = text.index(after: urlEnd)
        }
    }

    return tokens
}

private extension String {
    func trimmingTrailingSpacesAndTabs() -> String {
        var result = self
        while let last = result.last, last == " " || last == "\t" {
            result.removeLast()
        }
        return result
    }
}

private extension String {
    func firstMatch(pattern: String) -> [String]? {
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
