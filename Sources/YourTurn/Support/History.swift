import Foundation

/// Every send (and every discarded edit) is appended to history.jsonl, so nothing is lost for good.
enum History {
    static var fileURL: URL { Settings.folder.appendingPathComponent("history.jsonl") }

    static func record(title: String, result: WriteResult, to url: URL = History.fileURL) {
        var entry = result.json()
        entry["title"] = title
        entry["date"] = ISO8601DateFormatter().string(from: Date())
        guard let data = try? JSONSerialization.data(withJSONObject: entry) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data + Data([0x0A]))
            try? handle.close()
        } else {
            try? (data + Data([0x0A])).write(to: url)
        }
    }

    static func entries(from url: URL = History.fileURL) -> [[String: Any]] {
        guard let text = try? String(contentsOf: url) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
    }

    /// The last `count` entries, newest first, one line each, for `--history`.
    static func summary(count: Int, from url: URL = History.fileURL) -> String {
        entries(from: url).suffix(count).reversed().map { entry in
            let text = (entry["text"] as? String ?? "").split(separator: "\n").first.map(String.init) ?? ""
            return "\(entry["date"] ?? "")  \(entry["status"] ?? "")  \(entry["title"] ?? "")  \(text.prefix(70))"
        }.joined(separator: "\n")
    }
}
