import Foundation
import UIKit

/// Item images live as JPEG files in Documents/images; items store only the filenames.
enum ImageStore {
    private static let directory: URL = {
        let dir = URL.documentsDirectory.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let cache = NSCache<NSString, UIImage>()

    static func save(_ jpeg: Data) -> String? {
        let filename = "\(UUID().uuidString).jpg"
        do {
            try jpeg.write(to: directory.appendingPathComponent(filename))
            return filename
        } catch {
            return nil
        }
    }

    static func image(_ filename: String) -> UIImage? {
        if let cached = cache.object(forKey: filename as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent(filename).path) else { return nil }
        cache.setObject(image, forKey: filename as NSString)
        return image
    }

    static func delete(_ filenames: [String]) {
        for filename in filenames {
            cache.removeObject(forKey: filename as NSString)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
        }
    }
}
