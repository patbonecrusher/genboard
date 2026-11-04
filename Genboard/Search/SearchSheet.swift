import SwiftData
import SwiftUI

/// ⇧⌘F: one search box over every project. Choosing a result opens it where it lives.
struct SearchSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ResearchProject.createdAt, order: .reverse) private var projects: [ResearchProject]
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var hits: [ResearchSearch.Hit] { ResearchSearch.search(query, in: projects) }

    var body: some View {
        let hits = hits
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search pages, notes, cards, citations, theories…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .onSubmit { open(hits) }
                    .onKeyPress(.downArrow) { selection = min(selection + 1, max(hits.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
                    .onChange(of: query) { selection = 0 }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Search all your research", systemImage: "magnifyingglass",
                                       description: Text("Every project: pinned pages and their notes, transcriptions, cards, citations, connection notes, theories, session summaries and to-dos."))
                    .frame(maxHeight: .infinity)
            } else if hits.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                                SearchResultRow(hit: hit, isSelected: index == selection,
                                                showsProject: projects.count > 1)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selection = index
                                        open(hits)
                                    }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selection) { proxy.scrollTo(selection) }
                }
            }
            Divider()
            Text(hits.isEmpty ? " " : "\(hits.count) result\(hits.count == 1 ? "" : "s") · ↑↓ to choose, Return to open")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
        .frame(width: 640, height: 480)
        .onAppear {
            fieldFocused = true
            #if DEBUG
            if let demo = UserDefaults.standard.string(forKey: "GenboardDemoSearch") { query = demo }
            #endif
        }
    }

    private func open(_ hits: [ResearchSearch.Hit]) {
        guard hits.indices.contains(selection) else { return }
        let hit = hits[selection]
        dismiss()
        app.reveal(hit)
    }
}

private struct SearchResultRow: View {
    let hit: ResearchSearch.Hit
    let isSelected: Bool
    let showsProject: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: hit.symbol)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(hit.title).fontWeight(.medium).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(showsProject ? "\(hit.kind) · \(hit.project.name)" : hit.kind)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
                if !hit.snippet.isEmpty {
                    Text(hit.snippet)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                        .lineLimit(2)
                }
            }
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}
