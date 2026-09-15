import AppKit

/// Markdown ⇄ attributed text.
///
/// Paragraph model: a blank line separates paragraphs (one "\n" in the text view), a single newline
/// inside a paragraph is a soft break (U+2028), and every list line is its own paragraph.
/// Inline: bold, italic, links.
enum Markdown {
    static func attributed(from markdown: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (i, paragraph) in paragraphs(of: markdown).enumerated() {
            if i > 0 { out.append(NSAttributedString(string: "\n", attributes: TextStyle.typing)) }
            if let level = paragraph.heading {
                out.append(NSAttributedString(string: paragraph.text, attributes: TextStyle.headingAttributes(level)))
            } else {
                out.append(inline(paragraph.text))
            }
        }
        applyListStyles(out)
        return out
    }

    /// "## Title" → level 2 and "Title".
    static func heading(of line: String) -> (level: Int, body: String)? {
        guard let range = line.range(of: "^#{1,3} ", options: .regularExpression) else { return nil }
        return (line[range].count - 1, String(line[range.upperBound...]))
    }

    /// Splits Markdown into editor paragraphs.
    private static func paragraphs(of markdown: String) -> [(text: String, heading: Int?)] {
        var result: [(String, Int?)] = []
        var current: [String] = []
        func flush() {
            if !current.isEmpty { result.append((current.joined(separator: TextStyle.softBreak), nil)); current = [] }
        }
        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else if let item = Lists.fromMarkdown(line) {
                flush()
                result.append((item.kind.marker + item.body, nil))
            } else if let heading = heading(of: line) {
                flush()
                result.append((heading.body, heading.level))
            } else {
                current.append(line)
            }
        }
        flush()
        return result
    }

    /// Inline Markdown for one paragraph → attributed text with fonts and links.
    private static func inline(_ paragraph: String) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: paragraph, options: options) else {
            return NSAttributedString(string: paragraph, attributes: TextStyle.typing)
        }
        let out = NSMutableAttributedString(string: String(parsed.characters), attributes: TextStyle.typing)
        let fonts = NSFontManager.shared
        var location = 0
        for run in parsed.runs {
            let length = String(parsed[run.range].characters).utf16.count
            let range = NSRange(location: location, length: length)
            location += length
            var font = TextStyle.font
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { font = fonts.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = fonts.convert(font, toHaveTrait: .italicFontMask) }
            }
            out.addAttribute(.font, value: font, range: range)
            if let link = run.link {
                out.addAttribute(.link, value: link, range: range)
                out.addAttribute(.toolTip, value: link.absoluteString, range: range)
            }
        }
        return out
    }

    /// Hanging indent and a coloured marker on every list paragraph; the plain style elsewhere.
    /// The first item of a list keeps the paragraph gap above it; later items sit tight.
    static func applyListStyles(_ text: NSMutableAttributedString) {
        let string = text.string as NSString
        var position = 0
        var previousWasList = false
        while position < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: position, length: 0))
            if text.attribute(TextStyle.headingKey, at: paragraph.location, effectiveRange: nil) != nil {
                previousWasList = false
            } else if let item = Lists.prefix(of: string.substring(with: paragraph)) {
                let style = TextStyle.listParagraph.mutableCopy() as! NSMutableParagraphStyle
                if !previousWasList { style.paragraphSpacingBefore = TextStyle.paragraphGap }
                text.addAttribute(.paragraphStyle, value: style, range: paragraph)
                text.addAttribute(.foregroundColor, value: Theme.NS.accent, range: NSRange(location: paragraph.location, length: item.length - 1))
                previousWasList = true
            } else {
                text.addAttribute(.paragraphStyle, value: TextStyle.paragraph, range: paragraph)
                previousWasList = false
            }
            position = paragraph.location + max(paragraph.length, 1)
        }
    }

    /// Text inside curly braces: asides to the agent, not copy.
    static func asides(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: TextStyle.asidePattern) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map {
            let match = (text as NSString).substring(with: $0.range)
            return String(match.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    // MARK: Export

    private struct Run {
        var text: String
        var bold: Bool
        var italic: Bool
        var link: String?
        var style: String { "\(bold)\(italic)\(link ?? "")" }
    }

    /// Attributed text → Markdown. Emphasis never spans a line break.
    static func export(_ text: NSAttributedString) -> String {
        var runs: [Run] = []
        let fonts = NSFontManager.shared
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            let traits = fonts.traits(of: (attributes[.font] as? NSFont) ?? TextStyle.font)
            let link = (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String
            let isHeading = attributes[TextStyle.headingKey] != nil   // heading faces are bold; not emphasis
            let run = Run(text: (text.string as NSString).substring(with: range),
                          bold: !isHeading && traits.contains(.boldFontMask), italic: !isHeading && traits.contains(.italicFontMask), link: link)
            if let last = runs.last, last.style == run.style {
                runs[runs.count - 1].text += run.text
            } else {
                runs.append(run)
            }
        }

        // Wrap emphasis per line, keeping the separators ("\n" paragraph, U+2028 soft) in place.
        var raw = ""
        for run in runs {
            var line = ""
            for character in run.text {
                if character == "\n" || character == "\u{2028}" {
                    raw += wrap(line, run) + String(character)
                    line = ""
                } else {
                    line.append(character)
                }
            }
            raw += wrap(line, run)
        }

        // Heading levels per paragraph, in step with the raw paragraphs (same "\n" structure).
        var levels: [Int?] = []
        let string = text.string as NSString
        var position = 0
        while position < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: position, length: 0))
            levels.append(text.attribute(TextStyle.headingKey, at: paragraph.location, effectiveRange: nil) as? Int)
            position = paragraph.location + max(paragraph.length, 1)
        }
        // Items of the same list stay on consecutive lines; anything else gets a blank line between.
        let all = raw.components(separatedBy: "\n")
        let kept = all.indices.filter { !all[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        let paragraphs = kept.map { all[$0] }
        var out = ""
        for (i, paragraph) in paragraphs.enumerated() {
            if let level = levels.indices.contains(kept[i]) ? levels[kept[i]] : nil {
                out += String(repeating: "#", count: level) + " "
            }
            out += Lists.toMarkdown(paragraph).replacingOccurrences(of: TextStyle.softBreak, with: "\n")
            if i < paragraphs.count - 1 {
                let kind = Lists.prefix(of: paragraph)?.kind
                let nextKind = Lists.prefix(of: paragraphs[i + 1])?.kind
                out += kind?.sameList(as: nextKind) == true ? "\n" : "\n\n"
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wrap(_ line: String, _ run: Run) -> String {
        let core = line.trimmingCharacters(in: .whitespaces)
        guard !core.isEmpty else { return line }
        let leading = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let trailing = String(line.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
        var wrapped = core
        if let link = run.link { wrapped = "[\(wrapped)](\(link))" }
        if run.italic { wrapped = "*\(wrapped)*" }
        if run.bold { wrapped = "**\(wrapped)**" }
        return leading + wrapped + trailing
    }

    /// Notes the human attached to runs of text, with the quoted run and its range.
    static func notes(in text: NSAttributedString) -> [(quote: String, note: String, range: NSRange)] {
        var out: [(String, String, NSRange)] = []
        text.enumerateAttribute(TextStyle.noteKey, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let note = value as? String else { return }
            out.append(((text.string as NSString).substring(with: range), note, range))
        }
        return out
    }

    /// Every distinct link in a piece of text, in order of first appearance.
    static func links(in text: NSAttributedString) -> [(label: String, url: URL)] {
        var seen = Set<String>()
        var out: [(String, URL)] = []
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
            guard let url = url, seen.insert(url.absoluteString).inserted else { return }
            out.append(((text.string as NSString).substring(with: range), url))
        }
        return out
    }
}
