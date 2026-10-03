import SwiftUI
import SwiftData

struct ItemDetailView: View {
    let item: Item

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(EnrichmentTracker.self) private var tracker

    @State private var showingPicker = false
    @State private var confirmingDelete = false

    private var actions: StashActions { StashActions(context: context, tracker: tracker) }
    private var isRestashing: Bool { tracker.isRestashing(item.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ImageGallery(filenames: item.imageFilenames, fallbackTitle: item.title, isLoading: isRestashing)

                HStack(spacing: 10) {
                    PillButton(title: "Restash", systemImage: "sparkles", tint: .purple) { actions.restash(item) }
                    PillButton(title: "Move", systemImage: "square.stack.3d.up", tint: .blue) { showingPicker = true }
                    PillButton(title: "Delete", systemImage: "trash", tint: .red) { confirmingDelete = true }
                }
                .disabled(isRestashing)
                .opacity(isRestashing ? 0.5 : 1)

                categoryChip

                Text(item.itemDescription.isEmpty ? "No description yet." : item.itemDescription)
                    .foregroundStyle(item.itemDescription.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)

                if !item.facts.isEmpty {
                    FactsCard(facts: item.facts)
                }

                if let source = item.sourceURL, let url = URL(string: source) {
                    Link(destination: url) {
                        Label(url.host() ?? source, systemImage: "link").lineLimit(1)
                    }
                    .font(.footnote)
                }
            }
            .padding()
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPicker) {
            CategoryPickerView(currentCategory: item.category) { actions.move([item], to: $0) }
        }
        .confirmationDialog("Delete this item?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                actions.delete([item])
                dismiss()
            }
        }
    }

    private var categoryChip: some View {
        Button { showingPicker = true } label: {
            HStack(spacing: 6) {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                Text(item.category).font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemBackground), in: .capsule)
            .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

private struct FactsCard: View {
    let facts: [Fact]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 { Divider().opacity(0.4) }
                HStack(alignment: .top, spacing: 12) {
                    Text(fact.label.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .leading)
                    Text(fact.value)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16, style: .continuous))
    }
}
