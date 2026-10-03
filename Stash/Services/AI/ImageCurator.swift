import Foundation

/// Calls 2 and 3 of enrichment. The model, not hardcoded rules, decides which images belong:
///  1. `rank`: from every image URL found on the fetched pages, pick the likeliest photos of the item.
///  2. `verify`: look at the downloaded candidates and keep only the ones that actually show it.
enum ImageCurator {
    private static let maxCandidatesPerPage = 40

    /// Returns candidate image URLs, best first. Only URLs that appeared on the pages are returned.
    static func rank(title: String, summary: String, pages: [WebPage], limit: Int) async throws -> [URL] {
        var lookup: [String: URL] = [:]
        var listing = ""
        for (p, page) in pages.enumerated() {
            listing += "\nPage p\(p): \(page.url.absoluteString)\nTitle: \(page.title ?? "-")\n"
            for (c, candidate) in page.images.prefix(maxCandidatesPerPage).enumerated() {
                let id = "p\(p)c\(c)"
                lookup[id] = candidate.url
                listing += "\(id): \(candidate.url.absoluteString)\(candidate.context.isEmpty ? "" : "  [\(candidate.context)]")\n"
            }
        }
        guard !lookup.isEmpty else { return [] }

        let input = try await ClaudeAPI.callTool(
            model: Config.imageModel,
            system: """
            You pick photos for an item in a personal collection app. Given image URLs harvested \
            from web pages (with alt text or where on the page each was found), choose the ones \
            most likely to be a clear photo of the item itself: the product shot, the poster or \
            cover art, the dish or storefront. Skip logos, icons, UI sprites, ads, avatars, and \
            photos of other or related items. Prefer large/original renditions over thumbnails, \
            and avoid picking several sizes of the same image.
            """,
            content: [ClaudeAPI.text("Item: \(title)\n\(summary)\n\(listing)")],
            tool: ClaudeAPI.Tool(
                name: "choose_images",
                description: "Return candidate ids ranked best first.",
                schema: [
                    "type": "object",
                    "properties": [
                        "ids": ["type": "array", "items": ["type": "string"], "description": "Up to \(limit) candidate ids, best first."]
                    ],
                    "required": ["ids"]
                ]
            ),
            maxTokens: 512
        )
        let ids = input["ids"] as? [String] ?? []
        return ids.compactMap { lookup[$0] }.prefix(limit).map { $0 }
    }

    /// Returns indices into `previews` (small JPEGs) that clearly show the item, best first.
    static func verify(title: String, summary: String, previews: [Data]) async throws -> [Int] {
        var content: [[String: Any]] = [ClaudeAPI.text("Item: \(title)\n\(summary)")]
        for (i, preview) in previews.enumerated() {
            content.append(ClaudeAPI.text("Image \(i):"))
            content.append(ClaudeAPI.jpeg(preview))
        }
        let input = try await ClaudeAPI.callTool(
            model: Config.imageModel,
            system: """
            You check candidate photos for an item in a personal collection app. Keep only images \
            that clearly show this specific item, or for places its storefront, interior, or \
            signature food. Reject logos, unrelated photos, collages of other products, and \
            near-duplicates of an image you already kept. Order the keepers best first.
            """,
            content: content,
            tool: ClaudeAPI.Tool(
                name: "keep_images",
                description: "Return the indices of images to keep, best first.",
                schema: [
                    "type": "object",
                    "properties": ["indices": ["type": "array", "items": ["type": "integer"]]],
                    "required": ["indices"]
                ]
            ),
            maxTokens: 256
        )
        let indices = (input["indices"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.intValue }
        return indices.filter { previews.indices.contains($0) }
    }
}
