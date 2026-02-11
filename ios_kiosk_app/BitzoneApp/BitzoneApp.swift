import SwiftUI

@main
struct BitzoneApp: App {
    init() {
        Task { await VideoUpdater.checkAndUpdateIfNeeded() }
    }
    var body: some Scene {
        WindowGroup {
            BitzoneView()
        }
    }
}

