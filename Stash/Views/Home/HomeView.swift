import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Item.createdAt, order: .reverse) private var items: [Item]
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(EnrichmentTracker.self) private var tracker
    @State private var showingAdd = false
    @State private var showingReorganize = false

    /// Categories ordered by most recent addition; items within each stay newest first.
    private var categories: [(name: String, items: [Item])] {
        var order: [String] = []
        var grouped: [String: [Item]] = [:]
        for item in items {
            if grouped[item.category] == nil { order.append(item.category) }
            grouped[item.category, default: []].append(item)
        }
        return order.map { ($0, grouped[$0]!) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing stashed yet",
                        systemImage: "square.stack.3d.up",
                        description: Text("Tap + to add something you want to remember.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], spacing: 28) {
                            ForEach(categories, id: \.name) { category in
                                NavigationLink {
                                    CategoryDetailView(category: category.name)
                                } label: {
                                    CategoryStackView(name: category.name, items: category.items)
                                }
                                .buttonStyle(.plain)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding()
                        .animation(.stash, value: categories.map(\.name))
                    }
                }
            }
            .navigationTitle("Stash")
            .safeAreaInset(edge: .bottom) { PendingBanner() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingReorganize = true } label: {
                        Label("Reorganize", systemImage: "wand.and.stars")
                    }
                    .disabled(items.count < 2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) { AddItemView() }
            .sheet(isPresented: $showingReorganize) { ReorganizeSheet() }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                let actions = StashActions(context: context, tracker: tracker)
                for input in ShareInbox.drain() { actions.add(input) }
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(EnrichmentTracker())
        .modelContainer(for: Item.self, inMemory: true)
}
