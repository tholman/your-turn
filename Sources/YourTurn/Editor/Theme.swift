import AppKit
import SwiftUI

/// Colours and type. mymind's palette hue-rotated ~165°: its orange becomes teal. Installed faces only:
/// Charter for the one serif moment, Avenir Next for everything else.
enum Theme {
    /// AppKit-side colours, dynamic for light and dark. The paper theme swaps the light values for warm ones.
    enum NS {
        static var paper: Bool { Settings.shared.theme == .paper }
        static var canvas: NSColor    { dynamic(paper ? 0xF8F5EE : 0xFFFFFF, 0x171716) }
        static var sidebar: NSColor   { dynamic(paper ? 0xF1EDE3 : 0xFAFAF8, 0x1B1B1A) }
        static var hairline: NSColor  { dynamic(paper ? 0xE3DED1 : 0xECEAE5, 0x2A2927) }
        static var ink: NSColor       { dynamic(paper ? 0x2A2620 : 0x1A1918, 0xF2F1EE) }
        static var mute: NSColor      { dynamic(paper ? 0x8C8577 : 0x8A877F, 0x8C8983) }
        static var accent: NSColor    { dynamic(0x14A38F, 0x2CC4AE) }
        static var highlight: NSColor { dynamic(0xCDEFE8, 0x1F4A43) }
        static var barTop: NSColor    { dynamic(0xFEFEFE, 0x2E2D2B) }
        static var barBottom: NSColor { dynamic(paper ? 0xF0ECE2 : 0xEEEEEE, 0x232221) }
        static var barBorder: NSColor { dynamic(0xD0E2DC, 0x3A3F3D) }
        static var barIcon: NSColor   { dynamic(0x4A6560, 0xD6D4CF) }
        static var noteTint: NSColor  { dynamic(0xFFF3C4, 0x4A4020) }
        static var asideTint: NSColor { dynamic(0xD9F2EC, 0x1E3F39) }
        static var asideInk: NSColor  { dynamic(0x0F7D6D, 0x5BD6C0) }

        static func dynamic(_ light: Int, _ dark: Int) -> NSColor {
            NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            }
        }
    }

    static var canvas: Color   { Color(nsColor: NS.canvas) }
    static var sidebar: Color  { Color(nsColor: NS.sidebar) }
    static var hairline: Color { Color(nsColor: NS.hairline) }
    static var ink: Color      { Color(nsColor: NS.ink) }
    static var mute: Color     { Color(nsColor: NS.mute) }
    static var accent: Color   { Color(nsColor: NS.accent) }

    static func font(_ size: CGFloat, _ weight: String = "Regular") -> Font {
        Font.custom("AvenirNext-\(weight)", size: size)
    }

    static func serif(_ size: CGFloat) -> Font {
        Font.custom("Charter-Bold", size: size)
    }

    static func nsFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "AvenirNext-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
    }
}

/// Attributes for the editor's text. Shared by the text view, the Markdown importer and the exporter.
enum TextStyle {
    static var font: NSFont { Theme.nsFont(Settings.shared.textSize.points) }
    static let headingKey = NSAttributedString.Key("your-turn.heading")   // Int level 1…3
    static func headingFont(_ level: Int) -> NSFont {
        let size: CGFloat = level == 1 ? 26 : level == 2 ? 21 : 17
        return NSFont(name: "Charter-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
    }
    static var headingParagraph: NSParagraphStyle {
        let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
        style.paragraphSpacingBefore = 22
        style.lineHeightMultiple = 1.15
        return style
    }
    static func headingAttributes(_ level: Int) -> [NSAttributedString.Key: Any] {
        [.font: headingFont(level), .foregroundColor: NSColor.textColor, .paragraphStyle: headingParagraph, headingKey: level]
    }
    static let bullet = "•\t"
    static let softBreak = "\u{2028}"      // Shift+Return: a line break inside a paragraph
    static let listIndent: CGFloat = 24    // where list text starts
    static let markerIndent: CGFloat = 0   // the bullet or number sits flush with body text

    // Every gap lives BEFORE a paragraph. Pressing Return therefore never changes the line above,
    // and a line turned into a list item keeps the gap it already had (see RichTextView.insertText).
    static let paragraphGap: CGFloat = 12
    static let listGap: CGFloat = 2

    static var paragraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        // lineHeightMultiple, not lineSpacing: lineSpacing is skipped on a document's last line,
        // so the line would grow the moment another line appeared beneath it.
        style.lineHeightMultiple = 1.3
        style.paragraphSpacingBefore = paragraphGap
        style.paragraphSpacing = 0
        return style
    }

    static var listParagraph: NSParagraphStyle {
        let style = paragraph.mutableCopy() as! NSMutableParagraphStyle
        style.headIndent = listIndent
        style.firstLineHeadIndent = markerIndent
        style.paragraphSpacingBefore = listGap
        style.tabStops = [NSTextTab(textAlignment: .left, location: listIndent)]
        return style
    }

    /// Asides to the agent are written inline in curly braces: {make this punchier}.
    static let asidePattern = "\\{[^{}\\n]*\\}"

    static var typing: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
    }

    /// A note the human attached to a run of text. Not exported into the copy; returned alongside it.
    static let noteKey = NSAttributedString.Key("your-turn.note")
}

extension NSColor {
    convenience init(hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
