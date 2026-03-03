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

    private static let manifestURL = URL(string: "http://193.70.74.54:8000/eatbitz.json")!
    private static let versionKey = "com.bitzone.lastVideoHash"
    private static let fovKey = "com.bitzone.remoteFOV"
    private static let defaultFOV: Double = 45.0

    // MARK: - Download internals

    private var downloadSession: URLSession?
    private var downloadCompletion: ((URL?, Error?) -> Void)?
    private var updateTimer: Timer?

    // MARK: - Init

    override init() {
        super.init()
        // Restore last-known FOV from UserDefaults (works offline)
        let stored = UserDefaults.standard.double(forKey: Self.fovKey)
        if stored > 0 {
            remoteFOV = stored
        }
        
        // Start periodic checks
        startMonitoring()
    }
    
    private func startMonitoring() {
        // Run immediately
        Task {
            await checkAndUpdateIfNeeded()
        }
        
        // Schedule recurring check every hour (3600 seconds)
        // Note: Timer runs on the main run loop.
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.checkAndUpdateIfNeeded()
            }
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }

    // MARK: - Public API

    func checkAndUpdateIfNeeded() async {
        let currentlyDownloading = await MainActor.run { self.isDownloading }
        if currentlyDownloading {
            print("[VideoUpdater] ⚠️ Update already in progress – skipping check")
            return
        }

        print("[VideoUpdater] Checking for video update…")

        do {
            // 1. Fetch manifest JSON
            let (data, _) = try await URLSession.shared.data(from: Self.manifestURL)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let videoURLString = json["video_url"] as? String,
                  let videoURL = URL(string: videoURLString) else {
                print("[VideoUpdater] ⚠️ Invalid manifest format (missing video_url) – using stored video")
                return
            }

            // Extract remote version/hash as a string
            let remoteHash: String
            if let hash = json["hash"] as? String {
                remoteHash = hash
            } else if let version = json["version"] as? Int {
                remoteHash = String(version)
            } else if let version = json["version"] as? String {
                remoteHash = version
            } else {
                print("[VideoUpdater] ⚠️ Missing hash or version in manifest")
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

            print("[VideoUpdater] Remote hash: \(remoteHash)")
            
            // 2. Compare hash
            // If no hash is stored, we assume the baseline is the bundled version
            let storedHash = UserDefaults.standard.string(forKey: Self.versionKey) ?? ""
            let currentHash = storedHash.isEmpty ? VideoStore.bundledVersion : storedHash
            
            print("[VideoUpdater] Stored hash: \(storedHash)")
            print("[VideoUpdater] Current effective hash: \(currentHash)")

            guard remoteHash != currentHash else {
                print("[VideoUpdater] ✅ No update needed (Remote: \(remoteHash) matches Current: \(currentHash))")
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

            // 5. Persist the new hash
            UserDefaults.standard.set(remoteHash, forKey: Self.versionKey)

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
