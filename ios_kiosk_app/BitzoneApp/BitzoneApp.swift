import SwiftUI

@main
struct BitzoneApp: App {
    @StateObject private var videoUpdater = VideoUpdater()

    var body: some Scene {
        WindowGroup {
            BitzoneView(videoUpdater: videoUpdater)
                .task {
                    await videoUpdater.checkAndUpdateIfNeeded()
                }
        }
    }
}
