import Foundation
import Observation

/// In-flight enrichment work, for progress UI. Not persisted: if the app quits mid-enrichment
/// nothing is left stuck in a loading state.
@Observable
final class EnrichmentTracker {
    struct Job: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let itemID: UUID?
    }

    private(set) var jobs: [Job] = []
    /// Short-lived message for the banner, e.g. when an add turns out to be a duplicate.
    private(set) var notice: String?

    func start(_ label: String, itemID: UUID? = nil) -> Job.ID {
        let job = Job(label: label, itemID: itemID)
        jobs.append(job)
        return job.id
    }

    func finish(_ id: Job.ID) {
        jobs.removeAll { $0.id == id }
    }

    func isRestashing(_ itemID: UUID) -> Bool {
        jobs.contains { $0.itemID == itemID }
    }

    func notify(_ message: String) {
        notice = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if notice == message { notice = nil }
        }
    }
}
