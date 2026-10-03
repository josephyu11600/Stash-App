import Foundation
import SwiftData

struct Fact: Codable, Hashable {
    var label: String
    var value: String
}

@Model
final class Item {
    @Attribute(.unique) var id: UUID
    var title: String
    var itemDescription: String
    var category: String
    var sourceURL: String?
    var imageFilenames: [String]
    var facts: [Fact]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        itemDescription: String = "",
        category: String = "Uncategorized",
        sourceURL: String? = nil,
        imageFilenames: [String] = [],
        facts: [Fact] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.itemDescription = itemDescription
        self.category = category
        self.sourceURL = sourceURL
        self.imageFilenames = imageFilenames
        self.facts = facts
        self.createdAt = createdAt
    }
}

/// Value snapshot of an item, safe to hand to background work and the model.
struct ItemSummary: Codable, Sendable {
    let id: String
    let title: String
    let category: String

    init(_ item: Item) {
        id = item.id.uuidString
        title = item.title
        category = item.category
    }
}
