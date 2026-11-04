import SwiftData
import SwiftUI

/// Floating list of the project's theories. Clicking one makes it active: other cards dim, and new
/// cards and connections go into it. The active theory expands to show its evidence and to-dos.
struct TheoriesPanel: View {
    @Environment(AppState.self) private var app
    let project: ResearchProject

    private var theories: [Hypothesis] {
        project.hypotheses.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Theories").font(.headline)
                    Spacer()
                    Button { app.addHypothesis(to: project) } label: { Image(systemName: "plus") }
                        .help("New theory (starts from the selected card, if any)")
                    Button { app.showTheories = false } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)

                if theories.isEmpty {
                    Text("A theory is a statement you're testing, like “Olivine's father is Pierre Girard”. Press + to start one. While it's active, the cards and connections you add go into it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(theories) { theory in
                    let isActive = theory.persistentModelID == app.activeHypothesisID
                    TheoryRow(theory: theory, isActive: isActive)
                    if isActive {
                        TheoryDetail(theory: theory)
                            .padding(.horizontal, 6)  // matches the row padding, so fields line up with the highlighted row
                            .padding(.bottom, 6)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 290)
        .frame(maxHeight: 560)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
        .shadow(radius: 8, y: 2)
    }
}

private struct TheoryRow: View {
    @Environment(AppState.self) private var app
    let theory: Hypothesis
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(AppState.theoryColor(theory)).frame(width: 10, height: 10)
            Text(theory.title)
                .fontWeight(isActive ? .semibold : .regular)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { app.toggleActive(theory) }
                .help(isActive ? "Click to stop focusing on this theory" : "Click to focus on this theory")
            StrengthMeter(strength: theory.strength)
            Image(systemName: theory.status.symbol)
                .foregroundStyle(statusColor)
                .help(theory.status.label)
            Button { theory.isVisible.toggle(); app.save() } label: {
                Image(systemName: theory.isVisible ? "eye" : "eye.slash")
            }
            .buttonStyle(.borderless)
            .help(theory.isVisible ? "Hide this theory's cards" : "Show this theory's cards")
        }
        .padding(6)
        .background(isActive ? AppState.theoryColor(theory).opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .opacity(theory.isVisible ? 1 : 0.5)
    }

    private var statusColor: Color {
        switch theory.status {
        case .open: .secondary
        case .supported: .green
        case .refuted: .red
        }
    }
}

private struct TheoryDetail: View {
    @Environment(AppState.self) private var app
    @Bindable var theory: Hypothesis
    @State private var newTodo = ""
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Theory", text: $theory.title)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $theory.statement)
                .font(.callout)
                .frame(height: 54)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                .overlay(alignment: .topLeading) {
                    if theory.statement.isEmpty {
                        Text("Reasoning, what would prove or disprove it…")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .padding(5)
                            .allowsHitTesting(false)
                    }
                }
            Picker("Status", selection: Binding(get: { theory.status }, set: { theory.status = $0; app.save() })) {
                ForEach(HypothesisStatus.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("\(theory.cards.count) cards · \(theory.links.count) connections")
                .font(.caption)
                .foregroundStyle(.secondary)
            let strength = theory.strength
            HStack(spacing: 6) {
                StrengthMeter(strength: strength)
                Text("Evidence: \(strength.label.lowercased()) (\(strength.counts))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help("Weighed by source quality: an original record with primary information counts most, an online tree or a note little. Rate sources in each evidence card.")

            evidenceList("Evidence for", color: .green, cards: theory.evidence(.supports))
            evidenceList("Evidence against", color: .red,
                         cards: BoardCard.unique(theory.evidence(.contradicts) + theory.cards.filter { $0.flag == .conflict }))
            evidenceList("Open questions", color: .orange, cards: theory.cards.filter { $0.flag == .question })

            VStack(alignment: .leading, spacing: 4) {
                Text("To-dos").font(.caption.bold())
                ForEach(theory.todos.sorted { $0.createdAt < $1.createdAt }) { todo in
                    Toggle(todo.text, isOn: Binding(get: { todo.done }, set: { todo.done = $0; app.save() }))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
                TextField("Add a to-do, e.g. check 1861 St-Hugues baptisms", text: $newTodo)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit {
                        let text = newTodo.trimmingCharacters(in: .whitespaces)
                        if !text.isEmpty { app.addTodo(text, to: theory) }
                        newTodo = ""
                    }
            }

            Button("Delete Theory…", role: .destructive) { confirmDelete = true }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .font(.caption)
                .confirmationDialog("Delete “\(theory.title)”? Its cards stay on the board.", isPresented: $confirmDelete) {
                    Button("Delete Theory", role: .destructive) { app.delete(theory) }
                }
        }
    }

    @ViewBuilder
    private func evidenceList(_ title: String, color: Color, cards: [BoardCard]) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.bold()).foregroundStyle(color)
                ForEach(cards, id: \.persistentModelID) { card in
                    HStack(spacing: 4) {
                        Button(card.displayName) { app.selectedCardID = card.persistentModelID }
                            .buttonStyle(.borderless)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if card.kind == .evidence {
                            Text(card.evidenceRating).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }
}

/// Four bars filled by the strength of a theory's evidence; red when it's contested.
struct StrengthMeter: View {
    let strength: EvidenceStrength

    var body: some View {
        let filled = switch strength.level {
        case .none: 0
        case .contested, .weak: 1
        case .fair: 2
        case .strong: 4
        }
        let color: Color = strength.level == .contested ? .red : (strength.level >= .fair ? .green : .orange)
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < filled ? color : Color.secondary.opacity(0.25))
                    .frame(width: 3, height: 4 + CGFloat(index) * 2.5)
            }
        }
        .help("Evidence: \(strength.label.lowercased()) (\(strength.counts))")
    }
}
