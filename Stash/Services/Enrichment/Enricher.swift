import Foundation

struct EnrichedItem {
    let title: String
    let category: String
    let summary: String
    let facts: [Fact]
    let sourceURL: URL?
    let imageFilenames: [String]
}

enum EnrichmentOutcome {
    case enriched(EnrichedItem)
    case duplicate(of: UUID)
}

/// The enrichment pipeline. Each step degrades gracefully: a failed step leaves the item
/// with less detail rather than failing the add.
///
///   input ─▶ fetch source page (if a link)
///         ─▶ research: identify, categorize, describe, find photo pages     (Claude + web search)
///         ─▶ fetch photo pages, harvest every image URL on them
///         ─▶ rank candidates                                                  (Claude, text)
///         ─▶ download top candidates, verify which actually show the item    (Claude, vision)
///         ─▶ save up to `Config.maxImagesPerItem`
enum Enricher {
    private static let rankedCandidateLimit = 8
    private static let verifyLimit = 6

    static func run(input: String, existing: [ItemSummary], isRetry: Bool = false) async -> EnrichmentOutcome {
        let sourceURL = linkURL(in: input)
        let sourcePage: WebPage? = if let sourceURL { await WebPage.fetch(sourceURL) } else { nil }

        var research: ItemResearcher.Result?
        do {
            research = try await ItemResearcher.research(input: input, sourcePage: sourcePage, existing: existing, isRetry: isRetry)
        } catch {
            log("research failed: \(error.localizedDescription)")
        }
        if case .duplicate(let id)? = research?.kind {
            return .duplicate(of: id)
        }

        let title = research?.title.nilIfBlank ?? sourcePage?.title ?? input
        let summary = research?.summary.nilIfBlank ?? sourcePage?.description ?? ""
        let photoPages = await fetchPages(research?.photoPages ?? [])
        let pages = [sourcePage].compactMap { $0 } + photoPages
        log("\(pages.count) pages, \(pages.reduce(0) { $0 + $1.images.count }) image candidates")

        return .enriched(EnrichedItem(
            title: title,
            category: research?.category.nilIfBlank ?? "Uncategorized",
            summary: summary,
            facts: research?.facts ?? [],
            sourceURL: sourceURL,
            imageFilenames: await findImages(title: title, summary: summary, pages: pages)
        ))
    }

    /// Cleans up raw user/shared input. A search-results link (Google, Bing, DuckDuckGo...)
    /// becomes its query: those pages block plain fetches, and the terms are what matter.
    static func normalizedInput(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = linkURL(in: trimmed),
              url.path.isEmpty || url.path == "/" || url.path.contains("search"),
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value,
              !query.trimmingCharacters(in: .whitespaces).isEmpty
        else { return trimmed }
        return query
    }

    static func linkURL(in input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("http"), let url = URL(string: trimmed), url.host != nil else { return nil }
        return url
    }

    // MARK: - Images

    private static func findImages(title: String, summary: String, pages: [WebPage]) async -> [String] {
        var ranked: [URL]
        do {
            ranked = try await ImageCurator.rank(title: title, summary: summary, pages: pages, limit: rankedCandidateLimit)
        } catch {
            log("rank failed: \(error.localizedDescription)")
            // Without the model, the pages' own declared preview images are the best guess.
            ranked = pages.flatMap { $0.images.filter { $0.context.hasPrefix("meta") }.prefix(1).map(\.url) }
        }

        let downloaded = Array(await download(ranked).prefix(verifyLimit))
        log("ranked \(ranked.count), downloaded \(downloaded.count)")
        guard !downloaded.isEmpty else { return [] }

        var keep: [Int]
        do {
            keep = try await ImageCurator.verify(title: title, summary: summary, previews: downloaded.map(\.preview))
        } catch {
            log("verify failed: \(error.localizedDescription)")
            keep = Array(downloaded.indices)
        }
        // Rejecting everything usually means a strict judgment call on a plausible image;
        // the top-ranked candidate beats a blank tile.
        if keep.isEmpty { keep = [0] }
        log("kept \(keep.count) of \(downloaded.count)")

        return keep.prefix(Config.maxImagesPerItem).compactMap { ImageStore.save(downloaded[$0].full) }
    }

    // MARK: - Parallel fetches (results keep input order)

    private static func fetchPages(_ urls: [URL]) async -> [WebPage] {
        await withTaskGroup(of: (Int, WebPage?).self) { group in
            for (i, url) in urls.prefix(5).enumerated() {
                group.addTask { (i, await WebPage.fetch(url)) }
            }
            var results: [(Int, WebPage)] = []
            for await (i, page) in group {
                if let page { results.append((i, page)) }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func download(_ urls: [URL]) async -> [DownloadedImage] {
        await withTaskGroup(of: (Int, DownloadedImage?).self) { group in
            for (i, url) in urls.enumerated() {
                group.addTask { (i, await ImageDownloader.download(url)) }
            }
            var results: [(Int, DownloadedImage)] = []
            for await (i, image) in group {
                if let image { results.append((i, image)) }
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func log(_ message: String) {
        print("[Enricher] \(message)")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
