import SwiftUI

/// Reads a record with the AI, then lets the researcher pick which suggested cards to add.
struct SuggestionSheet: View {
    @Environment(AppState.self) private var app
    let request: SuggestionRequest
    @State private var suggestions: CardSuggestions?
    @State private var error: String?

    private var selectedCount: Int {
        guard let suggestions else { return 0 }
        return suggestions.people.filter(\.include).count + suggestions.events.filter(\.include).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested Cards").font(.title2.bold())
            Text("From \(request.card.displayName)")
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            } else if suggestions == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the record…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if suggestions != nil {
                suggestionList
            }

            HStack {
                Text("Nothing is added until you click Add.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { app.suggestionRequest = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Add \(selectedCount) Cards") {
                    if let suggestions { app.applySuggestions(suggestions, from: request.card) }
                    app.suggestionRequest = nil
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedCount == 0)
            }
        }
        .padding(20)
        .frame(width: 580)
        .task {
            do {
                suggestions = try await app.suggestCards(from: request.card)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var suggestionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let summary = suggestions?.summary, !summary.isEmpty {
                    Text(summary).font(.callout)
                }
                if let people = suggestions?.people, !people.isEmpty {
                    section("People")
                    ForEach(people.indices, id: \.self) { index in
                        personRow(people[index], include: include(person: index))
                    }
                }
                if let events = suggestions?.events, !events.isEmpty {
                    section("Events")
                    ForEach(events.indices, id: \.self) { index in
                        let event = events[index]
                        Toggle(isOn: include(event: index)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title.isEmpty ? event.type.capitalized : event.title).fontWeight(.medium)
                                let facts = [event.date, event.place].filter { !$0.isEmpty }.joined(separator: " · ")
                                if !facts.isEmpty { Text(facts).font(.caption).foregroundStyle(.secondary) }
                                if !event.participants.isEmpty, let suggestions {
                                    Text(event.participants.map { "\(suggestions.name(of: $0.person)) (\($0.role))" }
                                        .joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                if let relationships = suggestions?.relationships, !relationships.isEmpty, let suggestions {
                    section("Relationships")
                    ForEach(relationships.indices, id: \.self) { index in
                        let relationship = relationships[index]
                        Toggle(isOn: include(relationship: index)) {
                            Text("\(suggestions.name(of: relationship.from)) — \(relationship.role.label) → \(suggestions.name(of: relationship.to))")
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                if suggestions?.people.isEmpty == true && suggestions?.events.isEmpty == true {
                    Text("The AI didn't find people or events in this record.").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 440)
    }

    private func personRow(_ person: CardSuggestions.Person, include: Binding<Bool>) -> some View {
        Toggle(isOn: include) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(person.name).fontWeight(.medium)
                    if !person.role.isEmpty {
                        Text(person.role).font(.caption).foregroundStyle(.secondary)
                    }
                }
                let facts = [person.dates, person.place].filter { !$0.isEmpty }.joined(separator: " · ")
                if !facts.isEmpty { Text(facts).font(.caption).foregroundStyle(.secondary) }
                if let existing = person.existingCard {
                    Label("Already on the board as \(existing.displayName): will link to that card",
                          systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                if !person.notes.isEmpty { Text(person.notes).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .toggleStyle(.checkbox)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.subheadline.bold()).padding(.top, 2)
    }

    private func include(person index: Int) -> Binding<Bool> {
        Binding(get: { suggestions?.people[index].include ?? false }, set: { suggestions?.people[index].include = $0 })
    }

    private func include(event index: Int) -> Binding<Bool> {
        Binding(get: { suggestions?.events[index].include ?? false }, set: { suggestions?.events[index].include = $0 })
    }

    private func include(relationship index: Int) -> Binding<Bool> {
        Binding(get: { suggestions?.relationships[index].include ?? false },
                set: { suggestions?.relationships[index].include = $0 })
    }
}

/// Lists contradictions the local checks found; clicking one selects the cards involved.
struct ChecksPanel: View {
    @Environment(AppState.self) private var app
    let issues: [BoardIssue]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Checks").font(.headline)
                    Spacer()
                    Button { app.showChecks = false } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
                if issues.isEmpty {
                    Text("No contradictions found in the dates, ages and relationships on this board.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(issues) { issue in
                    Button {
                        app.selectedCardID = issue.cards.first?.persistentModelID
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: issue.kind == .contradiction ? "exclamationmark.triangle.fill" : "person.2.fill")
                                .foregroundStyle(issue.kind == .contradiction ? .orange : .blue)
                            Text(issue.message)
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text("Compares the years on person and event cards along their connections (birth, death, burial, marriage, parents).")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
        .frame(width: 290)
        .frame(maxHeight: 300)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
        .shadow(radius: 8, y: 2)
    }
}
