import SwiftUI

struct SessionView: View {
    @Environment(AppState.self) private var app
    let session: ResearchSession

    var body: some View {
        VStack(spacing: 0) {
            if !app.bannerDismissed, let last = app.lastTimeSession {
                LastTimeBanner(lastSession: last)
                Divider()
            }
            TabStrip()
            Divider()
            if app.mainMode == .board, let project = session.project {
                BoardView(project: project)
            } else if app.mainMode == .tree, let project = session.project {
                FamilyTreeView(project: project)
            } else if let tab = app.selectedTab {
                BrowserPane(tab: tab)
                    .id(tab.id)
            }
        }
        .navigationTitle(session.project?.name ?? "Genboard")
        // Session actions live in the address bar rather than the window toolbar: SwiftUI rebuilds
        // toolbar items on every focus change, which can loop AppKit's layout and crash the app.
    }
}

private struct TabStrip: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 0) {
            Button { app.showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.borderless)
                .help("Show or hide the projects sidebar")
                .padding(.horizontal, 8)
            Picker("View", selection: $app.mainMode) {
                Text("Browse").tag(MainMode.browse)
                Text("Board").tag(MainMode.board)
                Text("Tree").tag(MainMode.tree)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Switch between the browser (⌘1), the research board (⌘2) and the family tree (⌘3)")
            if app.mainMode == .browse {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(app.tabs) { tab in
                            TabButton(tab: tab, isSelected: tab.id == app.selectedTabID)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                Button { app.newTab() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("New tab (⌘T)")
                    .padding(.horizontal, 8)
            } else {
                Spacer()
            }
        }
        .frame(height: 32)
        .background(.bar)
    }
}

private struct TabButton: View {
    @Environment(AppState.self) private var app
    let tab: BrowserTab
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            if tab.isLoading {
                ProgressView().controlSize(.mini)
            }
            Text(tab.title)
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)
            Button { app.closeTab(tab) } label: { Image(systemName: "xmark").font(.caption2) }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { app.selectedTabID = tab.id }
    }
}

private struct BrowserPane: View {
    @Environment(AppState.self) private var app
    let tab: BrowserTab
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { tab.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!tab.canGoBack)
                Button { tab.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!tab.canGoForward)
                Button { tab.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(tab.url == nil)
                TextField("Address or search", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .focused($addressFocused)
                    .onSubmit {
                        if let url = Sites.url(fromAddressBar: address) { tab.load(url) }
                    }
                Menu {
                    ForEach(Sites.all) { site in
                        Button(site.name) { tab.load(site.url) }
                    }
                } label: {
                    Label("Sites", systemImage: "globe")
                }
                .fixedSize()
                Divider().frame(height: 18)
                Button { app.beginPin() } label: { Image(systemName: "pin") }
                    .help("Pin this page with a note on why it matters (⌘D)")
                    .disabled(tab.url == nil)
                Button { app.toggleDeadEnd() } label: { Image(systemName: "xmark.octagon") }
                    .help("Mark this page as a dead end (⇧⌘D)")
                    .disabled(tab.url == nil)
                Button { app.requestEndSession() } label: { Image(systemName: "stop.circle") }
                    .help("End the session and write where you left off (⇧⌘E)")
                Button { app.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }
                    .help("Show or hide the timeline and assistant")
            }
            .buttonStyle(.borderless)
            .padding(8)
            Divider()
            ZStack {
                WebView(webView: tab.webView)
                if tab.url == nil {
                    StartPage(tab: tab)
                }
            }
        }
        .onAppear { address = tab.url?.absoluteString ?? "" }
        .onChange(of: tab.url) { _, url in address = url?.absoluteString ?? "" }
        .onChange(of: app.stressFocusTick) { _, tick in addressFocused = tick.isMultiple(of: 2) }
    }
}

private struct StartPage: View {
    let tab: BrowserTab

    var body: some View {
        VStack(spacing: 20) {
            Text("Where to?").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230))], spacing: 12) {
                ForEach(Sites.all) { site in
                    Button { tab.load(site.url) } label: {
                        Label(site.name, systemImage: site.symbol)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: 600)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct LastTimeBanner: View {
    @Environment(AppState.self) private var app
    let lastSession: ResearchSession

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Last time · \(lastSession.startedAt.formatted(date: .abbreviated, time: .omitted)) · \(lastSession.goal)")
                    .font(.headline)
                Text(lastSession.summary.isEmpty ? "No summary was written." : lastSession.summary)
                    .textSelection(.enabled)
                if !lastSession.openQuestions.isEmpty {
                    Text("Open questions: \(lastSession.openQuestions)")
                        .foregroundStyle(.secondary)
                }
                if let todos = lastSession.project?.openTodos, !todos.isEmpty {
                    ForEach(todos.prefix(8)) { todo in
                        Toggle(todo.text, isOn: Binding(get: { todo.done }, set: { todo.done = $0 }))
                            .toggleStyle(.checkbox)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Button { app.bannerDismissed = true } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                if lastSession !== app.activeSession, !lastSession.savedTabURLs.isEmpty {
                    Button("Reopen \(lastSession.savedTabURLs.count) tabs") { app.reopenTabs(of: lastSession) }
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
    }
}
