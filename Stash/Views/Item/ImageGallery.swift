import SwiftUI

/// Swipeable item images in a fixed-height box. Images are scaled to fit inside it, so any
/// source size or aspect ratio is shown whole and never pushes the page wider than the screen.
struct ImageGallery: View {
    let filenames: [String]
    let fallbackTitle: String
    let isLoading: Bool

    private let height: CGFloat = 320

    var body: some View {
        Group {
            if filenames.count > 1 {
                TabView {
                    ForEach(filenames, id: \.self) { page($0) }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            } else {
                page(filenames.first)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay {
            if isLoading {
                RestashingOverlay().transition(.opacity)
            }
        }
        .animation(.stash, value: isLoading)
    }

    private func page(_ filename: String?) -> some View {
        StashThumbnail(filename: filename, fallbackTitle: fallbackTitle, cornerRadius: 16, contentMode: .fit)
    }
}

private struct RestashingOverlay: View {
    @State private var wiggle = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .rotationEffect(.degrees(wiggle ? 8 : -8))
                    Text("Restashing…").font(.subheadline.weight(.semibold))
                    Text("Finding better images & details").font(.caption).foregroundStyle(.secondary)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { wiggle = true }
            }
    }
}
