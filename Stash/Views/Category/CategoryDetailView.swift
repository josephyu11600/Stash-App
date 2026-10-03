import SwiftUI
import SwiftData

struct CategoryDetailView: View {
    let category: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(EnrichmentTracker.self) private var tracker
    @Query private var items: [Item]

    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var showingPicker = false

    private var actions: StashActions { StashActions(context: context, tracker: tracker) }
    private var selectedItems: [Item] { items.filter { selection.contains($0.id) } }

    init(category: String) {
        self.category = category
        _items = Query(
            filter: #Predicate<Item> { $0.category == category },
            sort: \Item.createdAt,
            order: .reverse
        )
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 16) {
                ForEach(items) { item in
                    cell(for: item)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding()
            .animation(.stash, value: items.map(\.id))
        }
        .navigationTitle(category)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                    selection.removeAll()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting && !selection.isEmpty {
                SelectionBar(
                    count: selection.count,
                    onMove: { showingPicker = true },
                    onDelete: { finish { actions.delete(selectedItems) } }
                )
            }
        }
        .animation(.stash, value: selection.isEmpty)
        .sheet(isPresented: $showingPicker) {
            CategoryPickerView(currentCategory: category) { newCategory in
                finish { actions.move(selectedItems, to: newCategory) }
            }
        }
        .onChange(of: items.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }

    @ViewBuilder
    private func cell(for item: Item) -> some View {
        if isSelecting {
            Button {
                if selection.remove(item.id) == nil { selection.insert(item.id) }
            } label: {
                ItemTile(item: item, selected: selection.contains(item.id))
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ItemDetailView(item: item)
            } label: {
                ItemTile(item: item)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) { actions.delete([item]) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func finish(_ action: () -> Void) {
        action()
        isSelecting = false
        selection.removeAll()
    }
}

private struct SelectionBar: View {
    let count: Int
    let onMove: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(count)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.accentColor, in: .circle)
            Text("selected")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            CircleIconButton(systemImage: "square.stack.3d.up", tint: .blue, action: onMove)
            CircleIconButton(systemImage: "trash", tint: .red, action: onDelete)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
