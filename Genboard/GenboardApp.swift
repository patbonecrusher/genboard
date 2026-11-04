import SwiftUI
import SwiftData

@main
struct GenboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Genboard", id: "main") {
            ContentView()
                .environment(delegate.appState)
                .environment(delegate.appState.aiSettings)
        }
        .defaultSize(width: 1320, height: 860)
        .modelContainer(delegate.appState.container)
        .commands { ResearchCommands(appState: delegate.appState) }

        Settings {
            SettingsView()
                .environment(delegate.appState.aiSettings)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        appState.handleQuitRequest()
    }
}

struct ResearchCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") { appState.newTab() }
                .keyboardShortcut("t")
                .disabled(appState.activeSession == nil)
        }
        CommandMenu("Research") {
            Button("Search All Research…") { appState.showSearch = true }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Divider()
            Button("Browse") { appState.mainMode = .browse }
                .keyboardShortcut("1")
                .disabled(appState.activeSession == nil)
            Button("Board") { appState.mainMode = .board }
                .keyboardShortcut("2")
                .disabled(appState.activeSession == nil)
            Button("Family Tree") { appState.mainMode = .tree }
                .keyboardShortcut("3")
                .disabled(appState.activeSession == nil)
            Divider()
            Button("Pin Page…") { appState.beginPin() }
                .keyboardShortcut("d")
                .disabled(appState.selectedTab?.url == nil)
            Button("Mark Dead End") { appState.toggleDeadEnd() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(appState.selectedTab?.url == nil)
            Divider()
            Button("End Session…") { appState.requestEndSession() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState.activeSession == nil)
            Divider()
            Button("Export Research Report…") { appState.reportProject = appState.activeSession?.project }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(appState.activeSession?.project == nil)
        }
    }
}
