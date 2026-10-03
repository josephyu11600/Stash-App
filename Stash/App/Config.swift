import Foundation

enum Config {
    /// Read from Secrets.plist, which is git-ignored (template: Secrets.example.plist at the repo
    /// root). It still ships inside the app bundle — fine for a personal build, not for distribution.
    static let claudeAPIKey: String = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return "" }
        return plist["CLAUDE_API_KEY"] as? String ?? ""
    }()

    /// Research call: web search, identification, categorization, finding pages with photos.
    /// Search quality matters most here, so it gets the stronger model.
    static let researchModel = "claude-sonnet-5-5"

    /// Image ranking and visual verification: cheap, fast, runs twice per add.
    static let imageModel = "claude-haiku-4-5-20251001"

    static let maxImagesPerItem = 3
}
