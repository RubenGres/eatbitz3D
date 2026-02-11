import Foundation

public struct VideoUpdater {

    // MARK: - Configuration

    /// URL pointing to the JSON manifest.
    private static let manifestURL = URL(string: "https://venn.bitz.tools/eatbitz.json")!

    /// UserDefaults key where we persist the last-known hash.
    private static let hashKey = "com.bitzone.lastVideoHash"

    // MARK: - Public API

    /// Called on app launch.
    /// 1. Fetch the remote JSON manifest.
    /// 2. Compare `hash` to the locally stored hash.
    /// 3. If different, download the new video and overwrite the local copy.
    /// 4. If the network is unreachable, silently fall back to the existing file.
    public static func checkAndUpdateIfNeeded() async {
        print("[VideoUpdater] Checking for video update…")

        do {
            // 1. Fetch manifest JSON
            let (data, _) = try await URLSession.shared.data(from: manifestURL)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let remoteHash = json["hash"] as? String,
                  let videoURLString = json["video_url"] as? String,
                  let videoURL = URL(string: videoURLString) else {
                print("[VideoUpdater] ⚠️ Invalid manifest format – using stored video")
                return
            }

            print("[VideoUpdater] Remote hash: \(remoteHash)")

            // 2. Compare hash
            let storedHash = UserDefaults.standard.string(forKey: hashKey)
            print("[VideoUpdater] Stored hash: \(storedHash ?? "none")")

            guard remoteHash != storedHash else {
                print("[VideoUpdater] ✅ Hash matches – no update needed")
                return
            }

            // 3. Download new video
            print("[VideoUpdater] ⬇️ New hash detected – downloading video…")
            let destination = VideoStore.localVideoURL

            // Ensure the parent directory exists
            let videosDir = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)

            let (tempFileURL, _) = try await URLSession.shared.download(from: videoURL)

            // Replace existing file
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempFileURL, to: destination)

            // 4. Persist the new hash
            UserDefaults.standard.set(remoteHash, forKey: hashKey)
            print("[VideoUpdater] ✅ Video updated successfully")

        } catch {
            // Network error or any other failure – fall back silently
            print("[VideoUpdater] ⚠️ Could not check for update: \(error.localizedDescription)")
            print("[VideoUpdater] Using stored/bundled video")
        }
    }
}
