import SwiftUI

/// Bottom-of-screen status: one row per in-flight enrichment, plus transient notices.
struct PendingBanner: View {
    @Environment(EnrichmentTracker.self) private var tracker

    var body: some View {
        VStack(spacing: 8) {
            ForEach(tracker.jobs) { job in
                row {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.itemID == nil ? "Stashing…" : "Restashing…")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(job.label).font(.subheadline).lineLimit(1)
                    }
                }
            }
            if let notice = tracker.notice {
                row {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(notice).font(.subheadline).lineLimit(2)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .animation(.stash, value: tracker.jobs)
        .animation(.stash, value: tracker.notice)
    }

    private func row(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 12) {
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 12, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
