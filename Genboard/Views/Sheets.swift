import SwiftUI

struct PinSheet: View {
    @Environment(AppState.self) private var app
    let draft: PinDraft
    @State private var note: String

    init(draft: PinDraft) {
        self.draft = draft
        _note = State(initialValue: draft.visit.note)
    }

    private var preview: NSImage? {
        if let png = draft.screenshotPNG { return NSImage(data: png) }
        return draft.visit.screenshotFile.flatMap(ScreenshotStore.image)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pin Page").font(.title2.bold())
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.visit.displayTitle).font(.headline)
                Text(draft.visit.urlString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Text("Why is this page important?").font(.subheadline.bold())
            TextEditor(text: $note)
                .font(.body)
                .frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            if !draft.selectedText.isEmpty {
                GroupBox("Selected text") {
                    ScrollView {
                        Text(draft.selectedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 80)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { app.pinDraft = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Pin") { app.savePin(draft, note: note) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("⌘↩")
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

struct CloseSessionSheet: View {
    @Environment(AppState.self) private var app
    @Environment(AISettings.self) private var aiSettings
    let session: ResearchSession
    @State private var whereLeftOff: String
    @State private var nextSteps = ""
    @State private var openQuestions: String
    @State private var keepTabs = true
    @State private var drafting = false
    @State private var draftError: String?

    init(session: ResearchSession) {
        self.session = session
        _whereLeftOff = State(initialValue: session.summary)
        _openQuestions = State(initialValue: session.openQuestions)
    }

    var body: some View {
        let visits = session.sortedVisits
        let pins = visits.filter { $0.mark == .pinned }
        let deadEnds = visits.filter { $0.mark == .deadEnd }.count

        VStack(alignment: .leading, spacing: 12) {
            Text("End Session").font(.title2.bold())

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Goal", value: session.goal)
                    LabeledContent("Duration", value: Duration.seconds(Date.now.timeIntervalSince(session.startedAt))
                        .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                    LabeledContent("Pages", value: "\(visits.count) visited · \(pins.count) pinned · \(deadEnds) dead ends")
                    if !pins.isEmpty {
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(pins) { pin in
                                    Label {
                                        VStack(alignment: .leading) {
                                            Text(pin.displayTitle)
                                            if !pin.note.isEmpty {
                                                Text(pin.note).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    } icon: {
                                        Image(systemName: "pin.fill").foregroundStyle(.orange)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 130)
                    }
                }
                .padding(4)
            }

            field("Where I left off", text: $whereLeftOff, height: 90)
            field("Next steps (one per line, each becomes a to-do)", text: $nextSteps, height: 70)
            field("Open questions", text: $openQuestions, height: 55)
            Toggle("Keep open tabs for next time", isOn: $keepTabs)

            if let draftError {
                Text(draftError).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Draft with AI", systemImage: "sparkles", action: draft)
                    .disabled(drafting || !aiSettings.hasAPIKey)
                    .help(aiSettings.hasAPIKey ? "Draft from this session's pages and notes" : "Add an API key in Settings")
                if drafting { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { app.cancelClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Skip Summary") {
                    app.finishClose(summary: "", nextSteps: [], openQuestions: "", keepTabs: keepTabs, skipped: true)
                }
                Button("Save & Close") {
                    let steps = nextSteps.split(separator: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
                        .filter { !$0.isEmpty }
                    app.finishClose(summary: whereLeftOff.trimmingCharacters(in: .whitespacesAndNewlines),
                                    nextSteps: steps,
                                    openQuestions: openQuestions.trimmingCharacters(in: .whitespacesAndNewlines),
                                    keepTabs: keepTabs, skipped: false)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(whereLeftOff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 580)
    }

    private func field(_ title: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.bold())
            TextEditor(text: text)
                .font(.body)
                .frame(height: height)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
    }

    private func draft() {
        drafting = true
        draftError = nil
        Task {
            defer { drafting = false }
            do {
                let result = try await app.draftSummary()
                whereLeftOff = result.whereLeftOff
                nextSteps = result.nextSteps.joined(separator: "\n")
                openQuestions = result.openQuestions.joined(separator: "\n")
            } catch {
                draftError = error.localizedDescription
            }
        }
    }
}
