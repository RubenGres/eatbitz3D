import Foundation
import CryptoKit

struct VideoMetadata: Decodable {
    let version: Int
    let videoURL: URL
    let sha256: String?
}

enum VideoStore {
    // TODO: Replace with your real metadata URL
    static let metadataURL = URL(string: "https://example.com/video/metadata.json")!
    static let localVersionKey = "bitzone_video_version"
    static let localFileName = "bitzone.mp4"

    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    static var localVideoURL: URL {
        documentsURL.appendingPathComponent(localFileName)
    }

    static func bundledVideoURL() -> URL? {
        Bundle.main.url(forResource: "bitzone", withExtension: "mp4")
    }

    static func currentLocalVersion() -> Int {
        UserDefaults.standard.integer(forKey: localVersionKey)
    }

    static func setLocalVersion(_ version: Int) {
        UserDefaults.standard.set(version, forKey: localVersionKey)
    }
}

enum VideoUpdater {
    static func checkAndUpdateIfNeeded() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: VideoStore.metadataURL)
            let metadata = try JSONDecoder().decode(VideoMetadata.self, from: data)
            let localVersion = VideoStore.currentLocalVersion()
            guard metadata.version > localVersion else { return }

            let (tempURL, _) = try await URLSession.shared.download(from: metadata.videoURL)

            // Optional: verify checksum if provided
            if let expected = metadata.sha256?.lowercased() {
                let actual = try sha256Hex(ofFileAt: tempURL).lowercased()
                guard actual == expected else {
                    throw NSError(domain: "VideoUpdater", code: -2, userInfo: [NSLocalizedDescriptionKey: "Checksum mismatch"])
                }
            }

            let fm = FileManager.default
            if fm.fileExists(atPath: VideoStore.localVideoURL.path) {
                try fm.removeItem(at: VideoStore.localVideoURL)
            }
            try fm.moveItem(at: tempURL, to: VideoStore.localVideoURL)
            VideoStore.setLocalVersion(metadata.version)
        } catch {
            // Silent failure; keep using existing video
            #if DEBUG
            print("Video update check failed: \(error)")
            #endif
        }
    }

    private static func sha256Hex(ofFileAt url: URL) throws -> String {
        // Minimal streaming hash to avoid loading entire file in memory
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = try? handle.read(upToCount: 1024 * 1024) // 1 MB chunks
            if let data, !data.isEmpty {
                hasher.update(data: data)
                return true
            } else {
                return false
            }
        }) { }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
