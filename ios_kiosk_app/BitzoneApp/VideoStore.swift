import Foundation

/// Provides locations for video assets used by Bitzone.
public enum VideoStore {
    /// The filename we expect for the primary 360 video.
    /// You can change this to match your actual asset name.
    private static let defaultFileName = "bitzone.mp4"

    /// URL in the app's Documents/videos directory where the updated video is stored.
    public static var localVideoURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let videosDir = docs.appendingPathComponent("videos", isDirectory: true)
        return videosDir.appendingPathComponent(defaultFileName)
    }

    /// Returns a URL for a bundled fallback video if present.
    /// Looks for common movie extensions in the main bundle.
    public static func bundledVideoURL() -> URL? {
        let candidates = [
            "mp4", "mov", "m4v"
        ]
        for ext in candidates {
            if let url = Bundle.main.url(forResource: defaultFileName.replacingOccurrences(of: ".mp4", with: ""), withExtension: ext) {
                return url
            }
        }
        return nil
    }
}
