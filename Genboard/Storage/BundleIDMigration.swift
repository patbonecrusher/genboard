import Foundation

/// Genboard 0.1 used the bundle ID `com.genboard.app`. The built-in browser's sign-ins (WebKit
/// data and cookies) and the preferences are filed under the bundle ID, so on first launch under
/// the new ID they are moved over once. The research store lives at a fixed path and is unaffected.
enum BundleIDMigration {
    static let oldID = "com.genboard.app"

    static func run() {
        guard let newID = Bundle.main.bundleIdentifier, newID != oldID else { return }
        let library = URL.libraryDirectory
        let moves = [
            ("WebKit/\(oldID)", "WebKit/\(newID)"),
            ("HTTPStorages/\(oldID).binarycookies", "HTTPStorages/\(newID).binarycookies"),
        ]
        for (old, new) in moves {
            let from = library.appending(path: old)
            let to = library.appending(path: new)
            guard FileManager.default.fileExists(atPath: from.path),
                  !FileManager.default.fileExists(atPath: to.path) else { continue }
            try? FileManager.default.moveItem(at: from, to: to)
        }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "MigratedFromOldBundleID"),
              let old = UserDefaults(suiteName: oldID)?.persistentDomain(forName: oldID) else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: "MigratedFromOldBundleID")
    }
}
