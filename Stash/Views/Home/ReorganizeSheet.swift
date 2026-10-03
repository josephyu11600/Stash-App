import SwiftUI
import SwiftData

/// Asks the model for a new grouping of the whole stash, previews it, and applies on confirm.
struct ReorganizeSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(EnrichmentTracker.self) private var tracker
    @Query private var items: [Item]

    private enum Phase {
        case thinking
        case failed(String)
        case proposal([CategoryOrganizer.Group])
    }

    @State private var phase = Phase.thinking

    private var itemsByID: [UUID: Item] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .thinking:
                    ProgressView {
                        Text("Reviewing \(items.count) items…")
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't reorganize", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { Task { await propose() } }
                    }
                case .proposal(let groups):
                    proposalView(groups)
                }
            }
            .navigationTitle("Reorganize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if case .proposal(let groups) = phase, moveCount(groups) > 0 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") { apply(groups) }.fontWeight(.semibold)
                    }
                }
            }
        }
        .task { await propose() }
    }

    // MARK: - Proposal

    private func proposalView(_ groups: [CategoryOrganizer.Group]) -> some View {
        let moves = moveCount(groups)
        let before = Set(items.map(\.category)).count
        return List {
            Section {
                Label(
                    moves == 0
                        ? "Already well organized — nothing to change."
                        : "\(moves) item\(moves == 1 ? "" : "s") move · \(before) → \(groups.count) categories",
                    systemImage: moves == 0 ? "checkmark.seal" : "wand.and.stars"
                )
                .font(.subheadline.weight(.medium))
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.itemIDs, id: \.self) { id in
                        if let item = itemsByID[id] { row(item, newCategory: group.name) }
                    }
                } header: {
                    HStack {
                        Text(group.name).font(.headline).foregroundStyle(.primary)
                        Spacer()
                        Text("\(group.itemIDs.count)").foregroundStyle(.secondary)
                    }
                    .textCase(nil)
                } footer: {
                    if !group.reason.isEmpty { Text(group.reason) }
                }
            }
        }
    }

    private func row(_ item: Item, newCategory: String) -> some View {
        HStack(spacing: 12) {
            StashThumbnail(filename: item.imageFilenames.first, fallbackTitle: item.title, cornerRadius: 8)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(1)
                if item.category != newCategory {
                    Text("from \(item.category)")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            }
        }
    }

    // MARK: - Actions

    private func moveCount(_ groups: [CategoryOrganizer.Group]) -> Int {
        groups.reduce(0) { count, group in
            count + group.itemIDs.filter { itemsByID[$0]?.category != group.name }.count
        }
    }

    private func propose() async {
        phase = .thinking
        let entries = items.map {
            CategoryOrganizer.Entry(id: $0.id, title: $0.title, category: $0.category, summary: $0.itemDescription)
        }
        do {
            phase = .proposal(try await CategoryOrganizer.propose(for: entries))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func apply(_ groups: [CategoryOrganizer.Group]) {
        var assignments: [UUID: String] = [:]
        for group in groups {
            for id in group.itemIDs { assignments[id] = group.name }
        }
        StashActions(context: context, tracker: tracker).recategorize(assignments)
        dismiss()
    }
}
