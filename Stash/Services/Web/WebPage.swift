import Foundation

/// A fetched web page reduced to what enrichment needs: basic text metadata and every
/// image URL it references. Harvesting is deliberately format-agnostic — deciding which
/// image is the right one is the model's job (see `ImageCurator`).
nonisolated struct WebPage: Sendable {
    let url: URL
    let title: String?
    let description: String?
    let images: [ImageCandidate]

    nonisolated struct ImageCandidate: Sendable, Hashable {
        let url: URL
        /// Where the URL was found, e.g. "meta og:image" or "img alt: Miffy plush". Helps the model choose.
        let context: String
    }

    static func fetch(_ url: URL) async -> WebPage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }
        return await parse(html: html, url: response.url ?? url)
    }

    @concurrent
    private static func parse(html raw: String, url: URL) async -> WebPage {
        // Undo the escaping that hides URLs inside inline JSON and attributes.
        let html = raw
            .replacingOccurrences(of: "\\u002F", with: "/", options: .caseInsensitive)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&amp;", with: "&")

        var metas: [String: String] = [:]
        var found: [ImageCandidate] = []
        var seen: Set<URL> = []
        func add(_ string: String, context: String) {
            guard let candidate = imageURL(string, base: url), seen.insert(candidate).inserted else { return }
            found.append(ImageCandidate(url: candidate, context: context))
        }

        // 1. <meta> tags — the page's own declared preview images come first.
        for tag in matches(#"<meta\b[^>]*>"#, in: html) {
            let attrs = attributes(of: tag)
            guard let key = attrs["property"] ?? attrs["name"] ?? attrs["itemprop"],
                  let content = attrs["content"] else { continue }
            metas[key.lowercased()] = decodeEntities(content)
            add(content, context: "meta \(key)")
        }

        // 2. <img> tags, with alt text as context.
        for tag in matches(#"<img\b[^>]*>"#, in: html) {
            let attrs = attributes(of: tag)
            let alt = attrs["alt"].map { "img alt: \(decodeEntities($0).prefix(80))" } ?? "img"
            for key in ["src", "data-src", "data-original"] {
                if let value = attrs[key] { add(value, context: alt) }
            }
            if let srcset = attrs["srcset"] ?? attrs["data-srcset"] {
                // Last srcset entry is conventionally the largest.
                if let largest = srcset.split(separator: ",").last?.split(separator: " ").first {
                    add(String(largest), context: alt)
                }
            }
        }

        // 3. Any other image-looking URL in the source (JSON-LD, preload hints, inline JSON...).
        for match in matches(#"https?://[^\s"'<>\\(){}|^`]+"#, in: html) {
            add(match, context: "")
        }

        let titleTag = matches(#"<title[^>]*>([^<]*)</title>"#, in: html, group: 1).first
        return WebPage(
            url: url,
            title: (metas["og:title"] ?? titleTag).map(decodeEntities)?.nilIfBlank,
            description: (metas["og:description"] ?? metas["description"])?.nilIfBlank,
            images: found
        )
    }

    // MARK: - Helpers

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "avif", "heic"]

    /// Resolves and upgrades a URL, returning it only if it plausibly points at a raster image.
    private static func imageURL(_ string: String, base: URL) -> URL? {
        let trimmed = decodeEntities(string).trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("data:"),
              var components = URL(string: trimmed, relativeTo: base)
                .flatMap({ URLComponents(url: $0.absoluteURL, resolvingAgainstBaseURL: true) }),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return nil }
        components.scheme = "https" // App Transport Security blocks plain http.
        guard let url = components.url else { return nil }

        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return url }
        guard ext.isEmpty else { return nil } // .js, .css, .svg, .html, ...
        // Extensionless image CDNs (e.g. /is/image/Brand/12345) — keep if the URL says "image".
        let lower = url.absoluteString.lowercased()
        return ["image", "img", "photo", "media"].contains(where: lower.contains) ? url : nil
    }

    private static func matches(_ pattern: String, in text: String, group: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: group), in: text).map { String(text[$0]) }
        }
    }

    private static func attributes(of tag: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: #"([a-zA-Z_:\-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')"#) else { return result }
        for match in regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let name = Range(match.range(at: 1), in: tag) else { continue }
            let valueRange = Range(match.range(at: 2), in: tag) ?? Range(match.range(at: 3), in: tag)
            if let valueRange { result[tag[name].lowercased()] = String(tag[valueRange]) }
        }
        return result
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
