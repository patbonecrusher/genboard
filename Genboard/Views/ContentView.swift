import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        // A plain HStack instead of NavigationSplitView + .inspector. Those are built on NSSplitView,
        // whose panes report min sizes back through nested hosting views; with wrapping text and a
        // web view inside, that feedback loop made AppKit kill the app. Fixed-width side panels
        // sidestep it entirely.
        HStack(spacing: 0) {
            if app.showSidebar || app.activeSession == nil {
                SidebarView()
                    .frame(width: 270)
                    .frame(maxHeight: .infinity)
                Divider()
            }
            Group {
                if let session = app.activeSession {
                    SessionView(session: session)
                } else {
                    ContentUnavailableView(
                        "No active session",
                        systemImage: "magnifyingglass",
                        description: Text("Pick a session in the sidebar to resume it, or start a new one in a project.")
                    )
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .clipped()
            if let session = app.activeSession, app.showInspector {
                Divider()
                InspectorView(session: session)
                    .frame(width: 360)
                    .frame(maxHeight: .infinity)
                    .clipped()
            }
        }
        .task { app.startSmokeTestIfRequested() }
        .sheet(isPresented: $app.showCloseSheet) {
            if let session = app.activeSession {
                CloseSessionSheet(session: session)
                    .interactiveDismissDisabled()
            }
        }
        .sheet(item: $app.pinDraft) { draft in
            PinSheet(draft: draft)
        }
        .sheet(item: $app.suggestionRequest) { request in
            SuggestionSheet(request: request)
        }
        .sheet(item: $app.reportProject) { project in
            ReportSheet(project: project)
        }
        .sheet(isPresented: $app.showSearch) {
            SearchSheet()
        }
        .alert("Backup", isPresented: Binding(
            get: { app.archiveMessage != nil },
            set: { if !$0 { app.archiveMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(app.archiveMessage ?? "")
        }
        .alert("AI error", isPresented: Binding(
            get: { app.aiErrorMessage != nil },
            set: { if !$0 { app.aiErrorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(app.aiErrorMessage ?? "")
        }
    }
}
