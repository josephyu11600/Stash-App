import SwiftUI

/// The one way item images are drawn. The parent decides the size; the image fills that
/// space and is clipped, so an image's own dimensions can never affect layout.
struct StashThumbnail: View {
    let filename: String?
    let fallbackTitle: String
    var cornerRadius: CGFloat = 12
    var contentMode: ContentMode = .fill

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if let filename, let image = ImageStore.image(filename) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    Text(fallbackTitle.prefix(1).uppercased())
                        .font(.largeTitle.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}
