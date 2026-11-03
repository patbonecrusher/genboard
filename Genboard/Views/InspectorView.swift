import SwiftUI

struct InspectorView: View {
    let session: ResearchSession
    @State private var panel = Panel.timeline

    enum Panel: String, CaseIterable {
        case timeline = "Timeline"
        case assistant = "Assistant"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $panel) {
                ForEach(Panel.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            switch panel {
            case .timeline: TimelineView(session: session)
            case .assistant: AssistantView(session: session)
            }
        }
    }
}

struct TimelineView: View {
    @Environment(AppState.self) private var app
    let session: ResearchSession
    @State private var showAllPages = false

    var body: some View {
        let visits = session.sortedVisits
        let shown = showAllPages ? visits : visits.filter { $0.mark != .none }
        let pinned = visits.filter { $0.mark == .pinned }.count
        let deadEnds = visits.filter { $0.mark == .deadEnd }.count

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.goal).font(.headline).lineLimit(3)
                Text("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(visits.count) pages · \(pinned) pinned · \(deadEnds) dead ends")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show all pages", isOn: $showAllPages)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            .padding(10)
            Divider()
            if shown.isEmpty {
                ContentUnavailableView(
                    "Nothing pinned yet",
                    systemImage: "pin",
                    description: Text("Pin pages that matter with ⌘D and mark dead ends with ⇧⌘D. Every page you open is still recorded; check “Show all pages” to see them.")
                )
            } else {
                // A plain stack, not List: List rows are separately hosted table cells, and rows whose
                // height depends on width (wrapping notes, screenshots) can loop AppKit's layout.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shown) { visit in
                            VisitRow(visit: visit)
                                .padding(.horizontal, 10)
                                .contentShape(Rectangle())
                                .onTapGesture { app.openVisit(visit) }
                                .draggable(visit.urlString)  // drop onto the board to make an evidence card
                                .contextMenu { menu(for: visit) }
                            Divider().padding(.leading, 34)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for visit: Visit) -> some View {
        Button(visit.mark == .pinned ? "Edit Note…" : "Pin with Note…") { app.editPin(visit) }
        if visit.mark != .deadEnd {
            Button("Mark Dead End") { app.setMark(.deadEnd, on: visit) }
        }
        if visit.mark != .none {
            Button("Clear Mark") { app.setMark(.none, on: visit) }
        }
        if visit.screenshotFile != nil {
            Divider()
            Button("Transcribe with AI") { Task { await app.transcribe(visit) } }
        }
        Divider()
        Button("Open in New Tab") { if let url = visit.url { app.addTab(url) } }
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(visit.urlString, forType: .string)
        }
    }
}

private struct VisitRow: View {
    @Environment(AppState.self) private var app
    let visit: Visit

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon.frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(visit.displayTitle)
                    .lineLimit(2)
                    .foregroundStyle(visit.mark == .deadEnd ? .secondary : .primary)
                Text("\(visit.site) · \(visit.visitedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !visit.note.isEmpty {
                    Text(visit.note)
                        .font(.callout)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
                if let file = visit.screenshotFile, let image = ScreenshotStore.image(file) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                if app.busyVisits.contains(visit.persistentModelID) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Transcribing…").font(.caption)
                    }
                } else if !visit.transcription.isEmpty {
                    DisclosureGroup("Transcription") {
                        Text(visit.transcription)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var icon: some View {
        switch visit.mark {
        case .pinned: Image(systemName: "pin.fill").foregroundStyle(.orange)
        case .deadEnd: Image(systemName: "xmark.octagon").foregroundStyle(.secondary)
        case .none: Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tertiary).padding(.top, 6)
        }
    }
}
