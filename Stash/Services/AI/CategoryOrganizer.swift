import Foundation

/// Proposes a fresh set of categories for the whole stash: split broad buckets that hide
/// distinct clusters, merge over-specific singletons, aim for groups of 2+ at the right level.
enum CategoryOrganizer {
    struct Entry {
        let id: UUID
        let title: String
        let category: String
        let summary: String
    }

    struct Group: Identifiable {
        let name: String
        let reason: String
        let itemIDs: [UUID]
        var id: String { name }
    }

    /// Every entry ends up in exactly one group. Items the model drops keep their current category.
    static func propose(for entries: [Entry]) async throws -> [Group] {
        // Short ids are cheaper and less error-prone for the model than UUIDs.
        let listing = entries.enumerated().map { i, e in
            "i\(i) | \(e.title) | \(e.category) | \(e.summary.prefix(120))"
        }.joined(separator: "\n")

        let input = try await ClaudeAPI.callTool(
            model: Config.researchModel,
            system: system,
            content: [ClaudeAPI.text("Items (id | title | current category | description):\n\(listing)")],
            tool: tool,
            maxTokens: 4096
        )
        return assemble(input, entries: entries)
    }

    private static let system = """
    You reorganize a personal "stash" app: things the user saved (restaurants, games, products, \
    books, places...). Reassign every item to a category so the collection is easy to browse.

    Goals, in priority order:
    1. Every category should hold 2 or more items. A singleton is acceptable only when nothing \
    else is remotely similar.
    2. Right level of specificity: split a broad bucket when it contains distinct clusters of 2+ \
    (e.g. "Products" holding plushies and pet food becomes "Plushies" and "Pet Supplies"); merge \
    over-specific categories into their natural parent (e.g. "Ramen Shops" with one item joins \
    "Restaurants").
    3. Stability: keep an existing category name when it already fits its items well.
    Names are 1-2 words, title case, natural plurals ("Games", "Restaurants").
    Assign every item id exactly once, then call reorganize.
    """

    private static let tool = ClaudeAPI.Tool(
        name: "reorganize",
        description: "The complete proposed grouping of all items.",
        schema: [
            "type": "object",
            "properties": [
                "groups": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"],
                            "reason": ["type": "string", "description": "One short sentence: what belongs here, or why it changed."],
                            "item_ids": ["type": "array", "items": ["type": "string"]]
                        ],
                        "required": ["name", "reason", "item_ids"]
                    ]
                ]
            ],
            "required": ["groups"]
        ]
    )

    private static func assemble(_ input: [String: Any], entries: [Entry]) -> [Group] {
        var assigned: Set<Int> = []
        var groups: [(name: String, reason: String, indices: [Int])] = []

        for raw in input["groups"] as? [[String: Any]] ?? [] {
            let name = ClaudeAPI.plainText(raw["name"] as? String ?? "")
            guard !name.isEmpty else { continue }
            let indices = (raw["item_ids"] as? [String] ?? []).compactMap { id -> Int? in
                guard id.hasPrefix("i"), let i = Int(id.dropFirst()), entries.indices.contains(i),
                      assigned.insert(i).inserted else { return nil }
                return i
            }
            guard !indices.isEmpty else { continue }
            if let existing = groups.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                groups[existing].indices += indices
            } else {
                groups.append((name, ClaudeAPI.plainText(raw["reason"] as? String ?? ""), indices))
            }
        }

        // Anything the model left out stays where it was.
        for i in entries.indices where !assigned.contains(i) {
            let current = entries[i].category
            if let existing = groups.firstIndex(where: { $0.name == current }) {
                groups[existing].indices.append(i)
            } else {
                groups.append((current, "Unchanged.", [i]))
            }
        }

        return groups
            .map { Group(name: $0.name, reason: $0.reason, itemIDs: $0.indices.map { entries[$0].id }) }
            .sorted { $0.itemIDs.count > $1.itemIDs.count }
    }
}
