import Foundation

/// Call 1 of enrichment: work out what the input actually is, describe and categorize it,
/// and find web pages likely to show a photo of it.
enum ItemResearcher {
    struct Result {
        enum Kind { case new, duplicate(of: UUID) }
        let kind: Kind
        let title: String
        let category: String
        let summary: String
        let facts: [Fact]
        let photoPages: [URL]
    }

    static func research(
        input: String,
        sourcePage: WebPage?,
        existing: [ItemSummary],
        isRetry: Bool
    ) async throws -> Result {
        var prompt = "Input: \(input)\n"
        if let sourcePage {
            prompt += "The input is a link. Page title: \(sourcePage.title ?? "unknown"). Page description: \(sourcePage.description ?? "none").\n"
        }
        prompt += "Existing categories: \(Set(existing.map(\.category)).sorted())\n"
        prompt += "Existing items: \(encode(existing))\n"
        if isRetry {
            prompt += "\nThis is a retry: the user wasn't happy with the previous result. Re-check what this is, and find different, higher-quality photo pages than the obvious first results.\n"
        }

        let input = try await ClaudeAPI.callTool(
            model: Config.researchModel,
            system: system,
            content: [ClaudeAPI.text(prompt)],
            tool: tool,
            webSearchUses: 4
        )
        return parse(input)
    }

    // MARK: - Prompt

    private static let system = """
    You file things into a personal "stash" app. The user saves anything they come across: \
    restaurants, movies, games, products, books, places, and so on.

    - If you aren't certain what the input refers to, use web search before deciding. Never infer \
    the category from the words alone ("incidents around the house" is a novel, not a home topic).
    - Category: the most specific group that still collects similar things. A Switch game goes in \
    "Games", a ramen shop in "Restaurants". Reuse an existing category only when it genuinely fits. \
    Treat broad buckets like "Products" or "Things" as a last resort.
    - Duplicates: only when it is clearly the same real-world thing as an existing item.
    - photo_pages: use search results to find pages that prominently show a photo of this exact \
    thing (official site, product listing, Wikipedia, store page, press). They will be fetched \
    without running JavaScript, so prefer ordinary server-rendered pages over social media and \
    app-like sites. Include only URLs you saw in search results or are certain exist.
    - All strings are plain text: no markup, no citation markers.
    Finish by calling record_item exactly once.
    """

    private static let tool = ClaudeAPI.Tool(
        name: "record_item",
        description: "Record the identified item, or flag it as a duplicate of an existing item.",
        schema: [
            "type": "object",
            "properties": [
                "action": ["type": "string", "enum": ["new", "duplicate"]],
                "duplicate_id": ["type": "string", "description": "Existing item id, when action is duplicate."],
                "title": ["type": "string", "description": "Properly formatted display name."],
                "category": ["type": "string", "description": "1-2 word title-case category."],
                "description": ["type": "string", "description": "2-3 sentences: what it is and why it's notable."],
                "facts": [
                    "type": "array",
                    "description": "2-5 category-appropriate facts you're confident in, e.g. Address/Cuisine for restaurants, Released/Director for movies, Platform/Developer for games.",
                    "items": [
                        "type": "object",
                        "properties": ["label": ["type": "string"], "value": ["type": "string"]],
                        "required": ["label", "value"]
                    ]
                ],
                "photo_pages": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Up to 5 page URLs that show a photo of this exact thing, best first."
                ]
            ],
            "required": ["action", "title", "category", "description", "facts", "photo_pages"]
        ]
    )

    // MARK: - Parsing

    private static func parse(_ input: [String: Any]) -> Result {
        let kind: Result.Kind
        if input["action"] as? String == "duplicate",
           let id = (input["duplicate_id"] as? String).flatMap(UUID.init(uuidString:)) {
            kind = .duplicate(of: id)
        } else {
            kind = .new
        }
        let facts = (input["facts"] as? [[String: Any]] ?? []).compactMap { raw -> Fact? in
            let label = ClaudeAPI.plainText(raw["label"] as? String ?? "")
            let value = ClaudeAPI.plainText(raw["value"] as? String ?? "")
            return label.isEmpty || value.isEmpty ? nil : Fact(label: label, value: value)
        }
        return Result(
            kind: kind,
            title: ClaudeAPI.plainText(input["title"] as? String ?? ""),
            category: ClaudeAPI.plainText(input["category"] as? String ?? ""),
            summary: ClaudeAPI.plainText(input["description"] as? String ?? ""),
            facts: facts,
            photoPages: (input["photo_pages"] as? [String] ?? []).compactMap(URL.init(string:))
        )
    }

    private static func encode(_ items: [ItemSummary]) -> String {
        (try? String(data: JSONEncoder().encode(items), encoding: .utf8)) ?? "[]"
    }
}
