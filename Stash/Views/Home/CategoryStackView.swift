import SwiftUI

/// A category on the home grid: its three newest items as an offset stack of tiles.
struct CategoryStackView: View {
    let name: String
    let items: [Item]

    var body: some View {
        let top = Array(items.prefix(3))
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                ForEach(Array(top.enumerated().reversed()), id: \.element.id) { index, item in
                    StashThumbnail(filename: item.imageFilenames.first, fallbackTitle: item.title, cornerRadius: 14)
                        .frame(width: 140, height: 140)
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        .rotationEffect(.degrees(Double(index) * 2.5))
                        .offset(x: CGFloat(index) * 6, y: CGFloat(index) * 6)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)

            HStack {
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(items.count)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
