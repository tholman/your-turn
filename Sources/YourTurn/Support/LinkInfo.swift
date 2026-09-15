import AppKit
import Combine

/// Fetches page titles for sidebar links and caches them on disk.
final class LinkInfo: ObservableObject {
    static let shared = LinkInfo()

    @Published private(set) var titles: [String: String] = [:]
    private var inflight = Set<String>()
    private let cacheURL: URL

    init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("your-turn")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cacheURL = directory.appendingPathComponent("links.json")
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            titles = cached
        }
    }

    func title(for url: URL) -> String? { titles[url.absoluteString] }

    func fetch(_ url: URL) {
        let key = url.absoluteString
        guard titles[key] == nil, !inflight.contains(key), url.scheme?.hasPrefix("http") == true else { return }
        inflight.insert(key)
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.setValue("Mozilla/5.0 your-turn", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let title = data.flatMap(Self.parseTitle)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.inflight.remove(key)
                if let title = title, !title.isEmpty {
                    self.titles[key] = title
                    self.save()
                }
            }
        }.resume()
    }

    static func parseTitle(_ data: Data) -> String? {
        let head = data.prefix(200_000)
        guard let html = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1),
              let range = html.range(of: "<title[^>]*>([^<]*)</title>", options: [.regularExpression, .caseInsensitive]) else { return nil }
        var title = String(html[range])
            .replacingOccurrences(of: "<title[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</title>", with: "", options: .caseInsensitive)
        let entities = [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")]
        for (entity, character) in entities { title = title.replacingOccurrences(of: entity, with: character) }
        return title.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func save() {
        if let data = try? JSONSerialization.data(withJSONObject: titles, options: [.sortedKeys]) { try? data.write(to: cacheURL) }
    }
}
