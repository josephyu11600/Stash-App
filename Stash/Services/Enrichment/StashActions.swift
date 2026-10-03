import SwiftUI
import SwiftData

/// Every mutation of the stash goes through here, so views stay presentation-only and
/// add/restash/move/delete behave the same wherever they're triggered.
struct StashActions {
    let context: ModelContext
    let tracker: EnrichmentTracker

    func add(_ rawInput: String) {
        let input = Enricher.normalizedInput(rawInput)
        guard !input.isEmpty else { return }
        let existing = allItems().map(ItemSummary.init)
        let job = tracker.start(input)

        Task {
            defer { tracker.finish(job) }
            switch await Enricher.run(input: input, existing: existing) {
            case .enriched(let result):
                let item = Item(
                    title: result.title,
                    itemDescription: result.summary,
                    category: result.category,
                    sourceURL: result.sourceURL?.absoluteString,
                    imageFilenames: result.imageFilenames,
                    facts: result.facts
                )
                withAnimation(.stash) { context.insert(item) }
            case .duplicate(let id):
                let title = allItems().first { $0.id == id }?.title ?? "That"
                tracker.notify("\(title) is already in your stash")
            }
        }
    }

    /// Re-runs enrichment in retry mode. Old images are kept unless new ones are found.
    func restash(_ item: Item) {
        guard !tracker.isRestashing(item.id) else { return }
        let input = item.sourceURL ?? item.title
        let existing = allItems().filter { $0.id != item.id }.map(ItemSummary.init)
        let job = tracker.start(item.title, itemID: item.id)

        Task {
            defer { tracker.finish(job) }
            guard case .enriched(let result) = await Enricher.run(input: input, existing: existing, isRetry: true) else { return }
            guard !item.isDeleted else {
                ImageStore.delete(result.imageFilenames)
                return
            }
            withAnimation(.stash) {
                item.title = result.title
                item.category = result.category
                item.itemDescription = result.summary
                item.facts = result.facts
                if !result.imageFilenames.isEmpty {
                    ImageStore.delete(item.imageFilenames)
                    item.imageFilenames = result.imageFilenames
                }
            }
        }
    }

    func move(_ items: [Item], to category: String) {
        withAnimation(.stash) {
            for item in items { item.category = category }
        }
    }

    /// Applies a full reorganization: item id → new category.
    func recategorize(_ assignments: [UUID: String]) {
        withAnimation(.stash) {
            for item in allItems() {
                if let category = assignments[item.id] { item.category = category }
            }
        }
    }

    func delete(_ items: [Item]) {
        withAnimation(.stash) {
            for item in items {
                ImageStore.delete(item.imageFilenames)
                context.delete(item)
            }
        }
    }

    private func allItems() -> [Item] {
        (try? context.fetch(FetchDescriptor<Item>())) ?? []
    }
}
