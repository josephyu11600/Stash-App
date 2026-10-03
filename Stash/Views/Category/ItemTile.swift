import SwiftUI

/// Square image with a fixed-height title below, so tiles in a row always line up.
struct ItemTile: View {
    let item: Item
    /// nil when not in selection mode.
    var selected: Bool? = nil

    @Environment(EnrichmentTracker.self) private var tracker

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StashThumbnail(filename: item.imageFilenames.first, fallbackTitle: item.title)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if let selected {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(selected ? Color.accentColor : .secondary)
                            .background(.regularMaterial, in: .circle)
                            .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if tracker.isRestashing(item.id) {
                        ProgressView()
                            .padding(6)
                            .background(.ultraThinMaterial, in: .circle)
                            .padding(6)
                    }
                }

            Text(item.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
