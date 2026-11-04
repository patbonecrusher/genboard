import Combine
import Sparkle
import SwiftUI

/// Sparkle updates for the direct download: checks the appcast on the website daily, and on demand
/// from Genboard ▸ Check for Updates…. Debug builds and test runs don't check unless
/// `-GenboardFeedURL` points them at a test feed.
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController!
    @Published private(set) var canCheck = false

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        guard Self.isEnabled else { return }
        controller.startUpdater()
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "GenboardCheckUpdatesNow") {
            Task {
                try? await Task.sleep(for: .seconds(2))
                checkForUpdates()
            }
        }
        #endif
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    private static var testFeedURL: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "GenboardFeedURL")
        #else
        nil
        #endif
    }

    private static var isEnabled: Bool {
        if AppState.isRunningTests { return false }
        #if DEBUG
        return testFeedURL != nil
        #else
        return true
        #endif
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        MainActor.assumeIsolated { Self.testFeedURL }
    }
}

struct UpdateCommands: Commands {
    @ObservedObject var updater: Updater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheck)
        }
    }
}
