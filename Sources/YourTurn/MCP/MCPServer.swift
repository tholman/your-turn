import Foundation

/// A minimal MCP server over stdio (newline-delimited JSON-RPC 2.0) exposing one tool, `your_turn_write`.
final class MCPServer {
    typealias Presenter = (WriteRequest, @escaping (WriteResult) -> Void) -> Void

    static let toolName = "your_turn_write"
    private static let knownVersions: Set<String> = ["2024-11-05", "2025-03-26", "2025-06-18"]

    /// Where replies go. Tests swap this for a capture.
    var output: (Data) -> Void = { FileHandle.standardOutput.write($0) }

    private let present: Presenter
    private let writeQueue = DispatchQueue(label: "your-turn.stdout")

    init(present: @escaping Presenter) {
        self.present = present
    }

    func start() {
        let thread = Thread { [weak self] in self?.readLoop() }
        thread.name = "your-turn.stdin"
        thread.start()
    }

    private func readLoop() {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: data) else {
                log("ignoring non-JSON line")
                continue
            }
            if let message = object as? [String: Any] {
                handle(message)
            } else if let batch = object as? [[String: Any]] {
                batch.forEach(handle)
            }
        }
        log("stdin closed, exiting")
        DispatchQueue.main.async { exit(0) }
    }

    func handle(_ message: [String: Any]) {
        // No method: a response to us, and we never send requests. No id: a notification.
        guard let method = message["method"] as? String, let id = message["id"] else { return }
        let params = (message["params"] as? [String: Any]) ?? [:]

        switch method {
        case "initialize":
            let requested = (params["protocolVersion"] as? String) ?? "2025-03-26"
            reply(id, [
                "protocolVersion": Self.knownVersions.contains(requested) ? requested : "2025-03-26",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "your-turn", "version": "1.0.0"],
                "instructions": Self.instructions,
            ])
        case "ping":
            reply(id, [String: Any]())
        case "tools/list":
            reply(id, ["tools": [Self.toolDefinition]])
        case "tools/call":
            call(id: id, params: params)
        default:
            replyError(id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func call(id: Any, params: [String: Any]) {
        let name = params["name"] as? String
        guard name == Self.toolName else {
            replyError(id, code: -32602, message: "Unknown tool: \(name ?? "nil")")
            return
        }
        let request: WriteRequest
        do {
            request = try WriteRequest.parse((params["arguments"] as? [String: Any]) ?? [:])
        } catch {
            reply(id, ["content": [["type": "text", "text": "\(Self.toolName): \(error.localizedDescription)"]], "isError": true])
            return
        }
        let run = {
            self.present(request) { result in
                self.reply(id, [
                    "content": [
                        ["type": "text", "text": result.summary()],
                        ["type": "text", "text": "```json\n\(result.jsonString())\n```"],
                    ],
                    "structuredContent": result.json(),
                    "isError": false,
                ])
            }
        }
        if Thread.isMainThread { run() } else { DispatchQueue.main.async(execute: run) }
    }

    // MARK: Writing

    private func reply(_ id: Any, _ result: [String: Any]) {
        send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func replyError(_ id: Any, code: Int, message: String) {
        let error: [String: Any] = ["code": code, "message": message]
        send(["jsonrpc": "2.0", "id": id, "error": error])
    }

    private func send(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        writeQueue.sync { output(data) }
    }

    // MARK: Tool definition

    static let instructions = """
    Your Turn puts a native panel in front of the human so they can write one piece of copy by hand. \
    Use `your_turn_write` whenever wording should come from the human rather than be invented: \
    a page's body copy, a headline, a bio, a tone-sensitive message, anything they said they want to write themselves. \
    One call = one piece of copy. Give the points it should hit as a checklist. The call blocks until they press Send or Cancel.
    """

    static let toolDefinition: [String: Any] = [
        "name": toolName,
        "description": """
        Pop up a native panel on the human's screen to write ONE piece of copy. The panel has a big writing area \
        (pre-filled with `draft` if given) and a sidebar checklist of `points` to hit, which the human ticks off as \
        they cover them. Returns the copy as Markdown, which points were ticked, `notes` attached to runs of the text, and \
        `asides`: anything the human wrote in {curly braces} is an instruction to you, not copy; strip the braces and \
        their contents before using the text. Blocks until they respond. \
        Use this instead of writing human-voiced copy yourself. One call per piece of copy: do not batch unrelated items. \
        Put constraints (length, tone, audience) in `context`, and URLs they might link to in `references`.
        """,
        "inputSchema": [
            "type": "object",
            "properties": [
                "title": ["type": "string", "description": "The name of the thing, short and clean: 'Tetrachord', 'About page'. No dashes or subtitles."],
                "context": ["type": "string", "description": "One to three sentences: where this copy lives, tone, length, audience."],
                "draft": ["type": "string", "description": "Optional starting text (Markdown: bold, italic, links, lists). Existing copy to edit, or an AI draft to rework."],
                "points": [
                    "type": "array",
                    "description": "Dot points the copy should hit. Shown as a checklist in the sidebar.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string", "description": "Stable id to match on when the result comes back."],
                            "label": ["type": "string", "description": "The point, short, e.g. 'Mention it is free'."],
                        ],
                        "required": ["label"],
                    ],
                ],
                "references": [
                    "type": "array",
                    "description": "Optional URLs the human may want to link to (pages on the site, sources). One click links the selected text.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "label": ["type": "string"],
                            "url": ["type": "string"],
                        ],
                        "required": ["url"],
                    ],
                ],
            ],
            "required": ["title"],
        ],
    ]
}
