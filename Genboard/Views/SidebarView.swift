import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \ResearchProject.createdAt, order: .reverse) private var projects: [ResearchProject]
    @State private var showingNewProject = false
    @State private var newProjectName = ""
    @State private var newSessionProject: ResearchProject?
    @State private var projectToDelete: ResearchProject?
    @State private var sessionToDelete: ResearchSession?

    var body: some View {
        List {
            ForEach(projects) { project in
                Section {
                    ForEach(project.sortedSessions) { session in
                        SessionRow(session: session, isActive: session === app.activeSession)
                            .contentShape(Rectangle())
                            .onTapGesture { app.open(session) }
                            .contextMenu {
                                Button("Delete Session…", role: .destructive) { sessionToDelete = session }
                            }
                    }
                    Button {
                        newSessionProject = project
                    } label: {
                        Label("New Session…", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text(project.name)
                        .contextMenu {
                            Button("New Session…") { newSessionProject = project }
                            Button("Export Research Report…") { app.reportProject = project }
                            Divider()
                            Button("Delete Project…", role: .destructive) { projectToDelete = project }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if projects.isEmpty {
                ContentUnavailableView {
                    Label("No projects", systemImage: "folder")
                } description: {
                    Text("Create a project for each research effort, like one family line.")
                } actions: {
                    Button("New Project") { showingNewProject = true }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Button {
                        showingNewProject = true
                    } label: {
                        Label("New Project", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button { app.showSearch = true } label: { Image(systemName: "magnifyingglass") }
                        .help("Search all research (⇧⌘F)")
                        .disabled(projects.isEmpty)
                }
                .buttonStyle(.borderless)
                .padding(10)
            }
            .frame(height: 40)
        }
        .alert("New Project", isPresented: $showingNewProject) {
            TextField("Name", text: $newProjectName)
            Button("Create") {
                let name = newProjectName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    let project = ResearchProject(name: name)
                    context.insert(project)
                    newSessionProject = project
                }
                newProjectName = ""
            }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        }
        .sheet(item: $newSessionProject) { project in
            NewSessionSheet(project: project)
        }
        .confirmationDialog("Delete this project and all its sessions?", isPresented: Binding(
            get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } }
        )) {
            Button("Delete Project", role: .destructive) {
                if let projectToDelete { app.delete(projectToDelete) }
            }
        }
        .confirmationDialog("Delete this session, its history and screenshots?", isPresented: Binding(
            get: { sessionToDelete != nil }, set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Delete Session", role: .destructive) {
                if let sessionToDelete { app.delete(sessionToDelete) }
            }
        }
    }
}

private struct SessionRow: View {
    let session: ResearchSession
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isActive ? "circle.fill" : "circle")
                .font(.system(size: 8))
                .foregroundStyle(isActive ? .green : .secondary)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.goal)
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(2)
                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let firstLine = session.summary.split(separator: "\n").first {
                    Text(firstLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if session.summarySkipped {
                    Text("No summary")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct NewSessionSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let project: ResearchProject
    @State private var goal = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Session").font(.title2.bold())
            Text(project.name).foregroundStyle(.secondary)
            TextField("Goal, e.g. Find the parents of Joseph Morel", text: $goal)
                .textFieldStyle(.roundedBorder)
                .onSubmit(start)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Start", action: start)
                    .keyboardShortcut(.defaultAction)
                    .disabled(goal.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func start() {
        let trimmed = goal.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        dismiss()
        app.startSession(in: project, goal: trimmed)
    }
}
