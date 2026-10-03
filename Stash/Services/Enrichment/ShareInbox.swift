import Foundation

/// Inputs queued by the share extension (`ShareQueue` in the StashShare target), handed over
/// through the App Group's shared defaults. Draining clears them so each is stashed once.
enum ShareInbox {
    private static let defaults = UserDefaults(suiteName: "group.jyu.Stash")
    private static let key = "pendingShares"

    static func drain() -> [String] {
        let pending = defaults?.stringArray(forKey: key) ?? []
        if !pending.isEmpty { defaults?.removeObject(forKey: key) }
        return pending
    }
}
