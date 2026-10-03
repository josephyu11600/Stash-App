import SwiftUI
import SwiftData

/// Sheet for choosing an existing category or naming a new one.
struct CategoryPickerView: View {
    let currentCategory: String?
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var allItems: [Item]
    @State private var newCategory = ""

    private var categories: [String] {
        Set(allItems.map(\.category)).sorted()
    }

    private var trimmedNewCategory: String {
        newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MOVE TO")
                            .font(.caption2.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                        Text("Choose a category")
                            .font(.title2.weight(.bold))
                    }

                    newCategoryField

                    FlowLayout(spacing: 8) {
                        ForEach(categories, id: \.self) { category in
                            chip(category)
                        }
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var newCategoryField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            TextField("New category name", text: $newCategory)
                .onSubmit { pick(trimmedNewCategory) }
            if !trimmedNewCategory.isEmpty {
                Button("Add") { pick(trimmedNewCategory) }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor, in: .capsule)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14, style: .continuous))
        .animation(.stash, value: trimmedNewCategory.isEmpty)
    }

    private func chip(_ category: String) -> some View {
        let isCurrent = category == currentCategory
        return Button { pick(category) } label: {
            HStack(spacing: 6) {
                if isCurrent {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold))
                }
                Text(category).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isCurrent ? Color.white : Color.primary)
            .background(isCurrent ? Color.accentColor : Color(.secondarySystemBackground), in: .capsule)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func pick(_ category: String) {
        guard !category.isEmpty else { return }
        onPick(category)
        dismiss()
    }
}
