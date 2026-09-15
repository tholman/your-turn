import Foundation

/// A dot point the human should hit while writing. Ticked off as they go.
struct Point: Identifiable {
    var id: String
    var label: String
}

/// A URL the human may want to link to.
struct Reference: Identifiable {
    var label: String
    var url: URL
    var id: String { url.absoluteString }
}

/// One piece of copy to write, with guidance.
struct WriteRequest {
    var title: String
    var context: String
    var draft: String
    var points: [Point]
    var references: [Reference] = []

    static func parse(_ dict: [String: Any]) throws -> WriteRequest {
        guard let title = dict["title"] as? String, !title.isEmpty else {
            throw NSError(domain: "your-turn", code: 1, userInfo: [NSLocalizedDescriptionKey: "`title` is required"])
        }
        var points: [Point] = []
        for (i, raw) in ((dict["points"] as? [[String: Any]]) ?? []).enumerated() {
            guard let label = raw["label"] as? String, !label.isEmpty else { continue }
            points.append(Point(id: (raw["id"] as? String) ?? "point-\(i + 1)", label: label))
        }
        var references: [Reference] = []
        for raw in (dict["references"] as? [[String: Any]]) ?? [] {
            guard let url = (raw["url"] as? String).flatMap(URL.init(string:)) else { continue }
            references.append(Reference(label: (raw["label"] as? String) ?? url.host ?? url.absoluteString, url: url))
        }
        return WriteRequest(
            title: title,
            context: (dict["context"] as? String) ?? "",
            draft: (dict["draft"] as? String) ?? "",
            points: points,
            references: references
        )
    }

    static let sample = WriteRequest(
        title: "Your Turn",
        context: "Editing the introduction of the Your Turn README.",
        draft: """
        A native Mac panel where the human writes the copy. An agent hands you a section of text, you write it in your own words, you send it back. {this is the line people read first, keep it tight}

        ## Why

        - Agents are fine at scaffolding and terrible at sounding like you.
        - Opening the editor to fix one paragraph breaks the flow.
        - The words that matter should be typed by the person whose name is on them.

        ## How it works

        The agent calls one tool with the section as it stands. A window opens, you write, you press Send, and the text goes back as Markdown, with your notes beside it.
        """,
        points: [
            Point(id: "mcp", label: "Say it works with any MCP client"),
            Point(id: "changes", label: "Mention the Changes view"),
        ],
        references: [
            Reference(label: "Your Turn on GitHub", url: URL(string: "https://github.com/tholman/your-turn")!),
            Reference(label: "Model Context Protocol", url: URL(string: "https://modelcontextprotocol.io")!),
        ]
    )
}
