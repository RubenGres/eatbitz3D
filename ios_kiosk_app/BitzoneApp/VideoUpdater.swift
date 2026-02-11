import Foundation
import Combine

/// Notification posted when a new video has been downloaded and is ready to play.
extension Notification.Name {
    static let videoDidUpdate = Notification.Name("com.bitzone.videoDidUpdate")
}

class VideoUpdater: NSObject, ObservableObject, URLSessionDownloadDelegate {

    // MARK: - Published state for UI

    @Published var isDownloading = false
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var remoteFOV: Double = 45.0

    // MARK: - Configuration

    private static let manifestURL = URL(string: "https://venn.bitz.tools/eatbitz.json")!
    private static let versionKey = "com.bitzone.lastVideoVersion"
    private static let fovKey = "com.bitzone.remoteFOV"
    private static let defaultFOV: Double = 45.0

    // MARK: - Download internals

    private var downloadSession: URLSession?
    private var downloadCompletion: ((URL?, Error?) -> Void)?

    // MARK: - Init

    override init() {
        super.init()
        // Restore last-known FOV from UserDefaults (works offline)
        let stored = UserDefaults.standard.double(forKey: Self.fovKey)
        if stored > 0 {
            remoteFOV = stored
        }
    }

    // MARK: - Public API

    func checkAndUpdateIfNeeded() async {
        print("[VideoUpdater] Checking for video update…")

        do {
            // 1. Fetch manifest JSON
            let (data, _) = try await URLSession.shared.data(from: Self.manifestURL)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let remoteVersion = (json["version"] as? Int) ?? (json["hash"] as? NSString)?.integerValue,
                  let videoURLString = json["video_url"] as? String,
                  let videoURL = URL(string: videoURLString) else {
                print("[VideoUpdater] ⚠️ Invalid manifest format (missing version or video_url) – using stored video")
                return
            }

            // Parse optional FOV (default to 45 if missing)
            let manifestFOV = (json["fov"] as? Double)
                ?? (json["fov"] as? Int).map(Double.init)
                ?? Self.defaultFOV
            print("[VideoUpdater] Remote FOV: \(manifestFOV)")

            // Always apply the FOV from manifest (even if video hash hasn't changed)
            UserDefaults.standard.set(manifestFOV, forKey: Self.fovKey)
            await MainActor.run {
                self.remoteFOV = manifestFOV
            }

            print("[VideoUpdater] Remote version: \(remoteVersion)")
            
            // 2. Compare version
            // If no version is stored, we assume the baseline is the bundled version
            let storedVersion = UserDefaults.standard.integer(forKey: Self.versionKey)
            let currentVersion = max(storedVersion, VideoStore.bundledVersion)
            
            print("[VideoUpdater] Stored version: \(storedVersion)")
            print("[VideoUpdater] Current effective version: \(currentVersion)")

            guard remoteVersion > currentVersion else {
                print("[VideoUpdater] ✅ No update needed (Remote: \(remoteVersion) <= Current: \(currentVersion))")
                return
            }

            // 3. Download new video with progress
            print("[VideoUpdater] ⬇️ New hash detected – downloading video…")
            await MainActor.run {
                self.isDownloading = true
                self.progress = 0.0
                self.statusMessage = "Downloading new video…"
            }

            let tempFileURL = try await downloadWithProgress(from: videoURL)

            await MainActor.run {
                self.statusMessage = "Installing update…"
            }

            // 4. Move to final location
            let destination = VideoStore.localVideoURL
            let videosDir = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempFileURL, to: destination)

            // 5. Persist the new version
            UserDefaults.standard.set(remoteVersion, forKey: Self.versionKey)

            await MainActor.run {
                self.progress = 1.0
                self.statusMessage = "Video updated!"
            }

            print("[VideoUpdater] ✅ Video updated successfully")

            // Brief pause so the user sees "Video updated!" before overlay dismisses
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            await MainActor.run {
                self.isDownloading = false
                self.statusMessage = ""
            }

            // 6. Notify the player to reload with the new video
            await MainActor.run {
                NotificationCenter.default.post(name: .videoDidUpdate, object: nil)
            }

        } catch {
            print("[VideoUpdater] ⚠️ Could not check for update: \(error.localizedDescription)")
            print("[VideoUpdater] Using stored/bundled video")
            await MainActor.run {
                self.isDownloading = false
                self.statusMessage = ""
            }
        }
    }

    // MARK: - Download with delegate-based progress

    private func downloadWithProgress(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.downloadCompletion = { fileURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let fileURL = fileURL {
                    continuation.resume(returning: fileURL)
                } else {
                    continuation.resume(throwing: NSError(domain: "VideoUpdater", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Download failed with no file"]))
                }
            }

            let config = URLSessionConfiguration.default
            let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.downloadSession = session
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The system deletes `location` after this method returns,
        // so move it to a temp path we control.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            try FileManager.default.moveItem(at: location, to: tempURL)
            downloadCompletion?(tempURL, nil)
        } catch {
            downloadCompletion?(nil, error)
        }
        downloadCompletion = nil
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let p: Double
        if totalBytesExpectedToWrite > 0 {
            p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            p = 0.0
        }
        DispatchQueue.main.async {
            self.progress = p
            let mb = Double(totalBytesWritten) / 1_000_000.0
            self.statusMessage = String(format: "Downloading… %.1f MB", mb)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            downloadCompletion?(nil, error)
            downloadCompletion = nil
        }
    }
}
