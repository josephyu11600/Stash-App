import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share sheet entry point. It only queues what was shared and confirms; the app runs
/// enrichment the next time it becomes active (see `ShareInbox` in the app target).
/// Extensions are short-lived and memory-limited, too fragile for the full pipeline.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        Task {
            let input = await sharedInput()
            if let input { ShareQueue.append(input) }
            show(SavedCard(input: input))
            try? await Task.sleep(for: .seconds(input == nil ? 2 : 1.2))
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func show(_ card: SavedCard) {
        let host = UIHostingController(rootView: card)
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    /// Prefers a URL attachment; falls back to shared text (which may itself contain a link).
    private func sharedInput() async -> String? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return url.absoluteString
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return firstLink(in: text) ?? text
            }
        }
        return nil
    }

    private func firstLink(in text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.url?.absoluteString
    }
}

/// Inputs waiting for the app to stash them. Shared with the app through the App Group;
/// the app side is `ShareInbox`, which reads and clears the same key.
enum ShareQueue {
    static func append(_ input: String) {
        let defaults = UserDefaults(suiteName: "group.jyu.Stash")
        let pending = defaults?.stringArray(forKey: "pendingShares") ?? []
        defaults?.set(pending + [input], forKey: "pendingShares")
    }
}

private struct SavedCard: View {
    let input: String?
    @State private var appeared = false

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: input == nil ? "exclamationmark.circle.fill" : "square.stack.3d.up.fill")
                    .font(.title)
                    .foregroundStyle(input == nil ? Color.orange : Color.accentColor)
                    .symbolEffect(.bounce, value: appeared)
                VStack(alignment: .leading, spacing: 2) {
                    Text(input == nil ? "Nothing to stash" : "Saved to Stash")
                        .font(.headline)
                    Text(input == nil ? "Share a link or some text." : "It'll be filled in when you open Stash.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .background(.regularMaterial, in: .rect(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
            .padding()
            .offset(y: appeared ? 0 : 200)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { appeared = true }
        }
    }
}
