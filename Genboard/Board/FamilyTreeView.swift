import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A pedigree (ancestors) or descendant chart generated from the board's person cards.
/// Competing parents from different theories are all drawn, in their theory colors.
struct FamilyTreeView: View {
    @Environment(AppState.self) private var app
    let project: ResearchProject
    @State private var exportMessage: String?

    private static let nodeSize = CGSize(width: 210, height: 58)
    private static let columnGap: CGFloat = 60
    private static let rowGap: CGFloat = 14

    var body: some View {
        let graph = FamilyGraph(project: project, includeRefuted: true)
        let root = graph.people.first { $0.persistentModelID == app.treeRootID }
            ?? graph.defaultRoot(selected: project.cards.first { $0.persistentModelID == app.selectedCardID })
        VStack(spacing: 0) {
            toolbar(graph: graph, root: root)
            Divider()
            if let root {
                let layout = Self.layout(root: root, graph: graph, descendants: app.treeShowsDescendants,
                                         generations: app.treeGenerations)
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        TreeLinesLayer(lines: layout.lines)
                            .frame(width: layout.size.width, height: layout.size.height)
                            .allowsHitTesting(false)
                        ForEach(layout.nodes) { node in
                            TreeNodeView(card: node.card, spouses: graph.spouses(of: node.card),
                                         isRoot: node.card === root,
                                         isSelected: node.card.persistentModelID == app.selectedCardID)
                                .frame(width: Self.nodeSize.width, height: Self.nodeSize.height)
                                .offset(x: node.origin.x, y: node.origin.y)
                                .onTapGesture(count: 2) { app.treeRootID = node.card.persistentModelID }
                                .onTapGesture { app.selectedCardID = node.card.persistentModelID }
                        }
                    }
                    .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                    .padding(24)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            } else {
                ContentUnavailableView {
                    Label("No family tree yet", systemImage: "person.3.sequence")
                } description: {
                    Text("Add person cards on the board and connect them with “parent of”, “child of” or “spouse of”. The tree is built from those connections.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("GEDCOM export", isPresented: Binding(get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(exportMessage ?? "")
        }
    }

    private func toolbar(graph: FamilyGraph, root: BoardCard?) -> some View {
        @Bindable var app = app
        return HStack(spacing: 12) {
            Menu {
                ForEach(graph.people, id: \.persistentModelID) { person in
                    Button(person.displayName) { app.treeRootID = person.persistentModelID }
                }
            } label: {
                Label(root?.displayName ?? "Choose a person", systemImage: "person.crop.circle")
            }
            .frame(maxWidth: 200, alignment: .leading)
            .disabled(graph.people.isEmpty)
            .help("The person the chart starts from. Double-click anyone in the tree to start from them.")
            Picker("Direction", selection: $app.treeShowsDescendants) {
                Text("Ancestors").tag(false)
                Text("Descendants").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Stepper("\(app.treeGenerations) gen.", value: $app.treeGenerations, in: 2...10)
                .fixedSize()
                .help("How many generations to show")
            Spacer(minLength: 8)
            Button(action: exportGedcom) { Label("GEDCOM", systemImage: "square.and.arrow.up") }
                .fixedSize()
                .help("Save the people, families, events and sources as a GEDCOM file for other genealogy software")
        }
        .lineLimit(1)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.bar)
    }

    private func exportGedcom() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ged") ?? .plainText]
        panel.nameFieldStringValue = "\(project.name).ged"
        panel.message = "Refuted theories and hidden theories are left out."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let export = GedcomExporter.export(project)
            try export.text.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Saved \(export.people) people and \(export.families) families to \(url.lastPathComponent)."
        } catch {
            exportMessage = "Couldn't save the file: \(error.localizedDescription)"
        }
    }

    // MARK: Layout

    struct Node: Identifiable {
        let id = UUID()
        let card: BoardCard
        let origin: CGPoint
    }

    struct Layout {
        var nodes: [Node] = []
        var lines: [TreeLinesLayer.Line] = []
        var size: CGSize = .zero
    }

    /// Each person sits centered on the span of the people they lead to (parents for a pedigree,
    /// children for descendants); people with none take the next free row. A person reached twice
    /// (cousin marriages) is drawn twice, as on a paper chart.
    static func layout(root: BoardCard, graph: FamilyGraph, descendants: Bool, generations: Int) -> Layout {
        var layout = Layout()
        var nextRow: CGFloat = 0
        let rowHeight = nodeSize.height + rowGap
        let columnWidth = nodeSize.width + columnGap

        @discardableResult
        func place(_ card: BoardCard, generation: Int, path: Set<ObjectIdentifier>) -> CGFloat {
            let next = generation + 1 < generations
                ? (descendants ? graph.children(of: card) : graph.parents(of: card))
                    .filter { !path.contains(ObjectIdentifier($0)) }
                : []
            let x = CGFloat(generation) * columnWidth
            let y: CGFloat
            if next.isEmpty {
                y = nextRow * rowHeight
                nextRow += 1
            } else {
                let path = path.union([ObjectIdentifier(card)])
                let ys = next.map { place($0, generation: generation + 1, path: path) }
                y = ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2
                for (relative, relativeY) in zip(next, ys) {
                    layout.lines.append(.init(
                        from: CGPoint(x: x + nodeSize.width, y: y + nodeSize.height / 2),
                        to: CGPoint(x: x + columnWidth, y: relativeY + nodeSize.height / 2),
                        color: relative.isRefuted ? .secondary.opacity(0.4) : theoryColor(of: relative, from: card)))
                }
            }
            layout.nodes.append(Node(card: card, origin: CGPoint(x: x, y: y)))
            return y
        }

        place(root, generation: 0, path: [])
        layout.size = CGSize(width: (layout.nodes.map(\.origin.x).max() ?? 0) + nodeSize.width,
                             height: max(nextRow, 1) * rowHeight)
        return layout
    }

    /// Lines into a parent that belongs to a theory take that theory's color.
    private static func theoryColor(of relative: BoardCard, from card: BoardCard) -> Color {
        let link = (card.outgoing + card.incoming).first { $0.from === relative || $0.to === relative }
        if let theory = link?.hypotheses.first(where: \.isVisible) ?? relative.hypotheses.first(where: \.isVisible) {
            return AppState.theoryColor(theory)
        }
        return .secondary
    }
}

struct TreeLinesLayer: View {
    struct Line {
        let from: CGPoint
        let to: CGPoint
        let color: Color
    }

    let lines: [Line]

    var body: some View {
        Canvas { context, _ in
            for line in lines {
                // An elbow: out from the person, across, then into the relative.
                let midX = (line.from.x + line.to.x) / 2
                var path = Path()
                path.move(to: line.from)
                path.addLine(to: CGPoint(x: midX, y: line.from.y))
                path.addLine(to: CGPoint(x: midX, y: line.to.y))
                path.addLine(to: line.to)
                context.stroke(path, with: .color(line.color), lineWidth: 1.5)
            }
        }
    }
}

private struct TreeNodeView: View {
    let card: BoardCard
    let spouses: [BoardCard]
    let isRoot: Bool
    let isSelected: Bool

    private var theories: [Hypothesis] {
        card.hypotheses.filter(\.isVisible).sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: card.sex == .female ? "figure.stand.dress" : (card.sex == .male ? "figure.stand" : "person.fill"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(card.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                ForEach(theories) { theory in
                    Circle().fill(AppState.theoryColor(theory)).frame(width: 7, height: 7).help(theory.title)
                }
            }
            let facts = [card.date, card.place].filter { !$0.isEmpty }.joined(separator: " · ")
            if !facts.isEmpty {
                Text(facts).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if !spouses.isEmpty {
                Text("⚭ " + spouses.map(\.displayName).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(Color(nsColor: .controlBackgroundColor))
                shape.fill(Color.blue.opacity(isRoot ? 0.22 : 0.10))
            }
        }
        .overlay {
            let theory = theories.first
            shape.stroke(isSelected ? Color.accentColor : (theory.map(AppState.theoryColor) ?? Color.primary.opacity(0.15)),
                         style: StrokeStyle(lineWidth: isSelected || theory != nil ? 2 : 1,
                                            dash: !isSelected && theory?.status == .open ? [5, 3] : []))
        }
        .opacity(card.isRefuted ? 0.45 : 1)
        .contentShape(shape)
    }
}
