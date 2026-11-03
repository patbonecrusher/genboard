import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A freeform research board: people, events, evidence and notes, connected by meaning.
/// Pure SwiftUI on purpose (no AppKit-backed lists or split views), with links drawn in a Canvas.
struct BoardView: View {
    @Environment(AppState.self) private var app
    let project: ResearchProject

    @State private var cardSizes: [PersistentIdentifier: CGSize] = [:]
    @State private var dragOffsets: [PersistentIdentifier: CGSize] = [:]
    @State private var panStart: CGSize?
    @State private var viewport: CGSize = .zero
    @State private var importError: String?
    @State private var hoveredCardID: PersistentIdentifier?
    @State private var hoveredHandleID: PersistentIdentifier?
    @GestureState private var magnification: CGFloat = 1

    private var zoom: CGFloat {
        min(max(app.boardZoom * magnification, AppState.zoomRange.lowerBound), AppState.zoomRange.upperBound)
    }

    /// Cards not hidden by a hidden theory.
    private var visibleCards: [BoardCard] {
        project.cards.filter { !$0.isHiddenByTheories }
    }

    private var activeTheory: Hypothesis? { app.activeHypothesis(in: project) }

    private var selectedCard: BoardCard? {
        project.cards.first { $0.persistentModelID == app.selectedCardID }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
        }
        .alert("Import failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK") {}
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Person", systemImage: CardKind.person.symbol) { add(.person) }
                Button("Event", systemImage: CardKind.event.symbol) { add(.event) }
                Button("Note", systemImage: CardKind.note.symbol) { add(.note) }
                Divider()
                let pins = pinnedVisits
                if pins.isEmpty {
                    Text("No pinned pages yet")
                } else {
                    Menu("Evidence from a Pinned Page") {
                        ForEach(pins) { visit in
                            Button(visit.displayTitle) { app.addEvidenceCard(for: visit, at: newCardPoint(), in: project) }
                        }
                    }
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .fixedSize()
            .help("Add a card. You can also drag pinned pages here from the Timeline.")
            Button { app.showTheories.toggle() } label: {
                Label("Theories", systemImage: "lightbulb")
                    .symbolVariant(app.showTheories ? .fill : .none)
            }
            .fixedSize()
            .help("Show or hide the theories panel")
            let issueCount = BoardChecks.run(project).count
            Button { app.showChecks.toggle() } label: {
                HStack(spacing: 4) {
                    Label("Checks", systemImage: "checkmark.shield")
                    if issueCount > 0 {
                        Text("\(issueCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .background(.orange, in: Capsule())
                    }
                }
            }
            .fixedSize()
            .help("Contradictions in dates, ages and relationships")
            Button { importScapple() } label: { Image(systemName: "square.and.arrow.down") }
                .help("Import a Scapple board…")
            Spacer(minLength: 8)
            Button { setZoom(app.boardZoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
            Button { setZoom(1) } label: { Text("\(Int((zoom * 100).rounded()))%").monospacedDigit().frame(width: 44) }
                .help("Actual size")
            Button { setZoom(app.boardZoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
            Button("Fit", action: fitToView)
                .fixedSize()
        }
        .lineLimit(1)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.bar)
    }

    // MARK: Canvas

    private var canvas: some View {
        let frames = cardFrames
        let issues = BoardChecks.run(project)
        let flaggedCards = Set(issues.flatMap(\.cards).map(ObjectIdentifier.init))
        return ZStack(alignment: .topLeading) {
            Color(nsColor: .underPageBackgroundColor)
                .contentShape(Rectangle())
                .gesture(panGesture)
                .onTapGesture { app.selectedCardID = nil }
                // The board is an overlay so its size (as big as all the cards) never affects layout:
                // as a ZStack sibling it made the stack wider than the view, which then got centered.
                .overlay(alignment: .topLeading) { boardContent(frames: frames, flaggedCards: flaggedCards) }

            if project.cards.isEmpty {
                ContentUnavailableView {
                    Label("Empty board", systemImage: "rectangle.3.group")
                } description: {
                    Text("Add people, events and notes, drag pinned pages here from the Timeline, or import a Scapple board.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 10) {
                if app.showTheories { TheoriesPanel(project: project) }
                if app.showChecks { ChecksPanel(issues: issues) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)

            if let card = selectedCard {
                CardEditor(card: card, project: project)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(10)
            }
        }
        .clipped()
        .coordinateSpace(.named(Self.viewportSpace))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            let firstLayout = viewport == .zero
            viewport = size
            if firstLayout { fitIfNothingVisible() }
        }
        .gesture(
            MagnifyGesture()
                .updating($magnification) { value, state, _ in state = value.magnification }
                .onEnded { setZoom(app.boardZoom * $0.magnification) }
        )
        .dropDestination(for: String.self) { items, location in
            dropPages(items, at: location)
        }
    }

    private func boardContent(frames: [PersistentIdentifier: CGRect], flaggedCards: Set<ObjectIdentifier>) -> some View {
        ZStack(alignment: .topLeading) {
            BoardLinksLayer(links: linkGeometry(frames: frames))
                .frame(width: boardSize(frames).width, height: boardSize(frames).height)
                .allowsHitTesting(false)
            ForEach(visibleCards) { card in
                let id = card.persistentModelID
                BoardCardView(card: card, isSelected: id == app.selectedCardID,
                              dimmed: activeTheory.map { theory in !card.hypotheses.contains { $0 === theory } } ?? false,
                              hasIssue: flaggedCards.contains(ObjectIdentifier(card)),
                              isLinkTarget: linkTarget(frames: frames)?.persistentModelID == id)
                    .frame(width: card.width)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSizes[id] = $0 }
                    .onHover { inside in
                        if inside { hoveredCardID = id } else if hoveredCardID == id { hoveredCardID = nil }
                    }
                    .overlay(alignment: .trailing) {
                        // Placed before .offset so it moves with the card.
                        if showsHandle(for: id) {
                            ConnectHandle(zoom: zoom)
                                .offset(x: 7 / zoom)
                                .onHover { inside in
                                    if inside { hoveredHandleID = id } else if hoveredHandleID == id { hoveredHandleID = nil }
                                }
                                .gesture(linkDrag(from: card))
                        }
                    }
                    .offset(x: card.x + (dragOffsets[card.persistentModelID]?.width ?? 0),
                            y: card.y + (dragOffsets[card.persistentModelID]?.height ?? 0))
                    .gesture(cardDrag(card))
                    .onTapGesture { tap(card) }
            }
            if let draft = app.linkDraft, let source = frames[draft.from] {
                Path { path in
                    path.move(to: CGPoint(x: source.maxX, y: source.midY))
                    path.addLine(to: draft.point)
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2 / zoom, lineCap: .round, dash: [6 / zoom, 4 / zoom]))
                .allowsHitTesting(false)
            }
        }
        .frame(width: boardSize(frames).width, height: boardSize(frames).height, alignment: .topLeading)
        .scaleEffect(zoom, anchor: .topLeading)
        .offset(app.boardPan)
    }

    // MARK: Geometry

    private var cardFrames: [PersistentIdentifier: CGRect] {
        Dictionary(uniqueKeysWithValues: visibleCards.map { card in
            let id = card.persistentModelID
            let offset = dragOffsets[id] ?? .zero
            let size = cardSizes[id] ?? CGSize(width: card.width, height: 60)
            return (id, CGRect(x: card.x + offset.width, y: card.y + offset.height, width: size.width, height: size.height))
        })
    }

    private func boardSize(_ frames: [PersistentIdentifier: CGRect]) -> CGSize {
        CGSize(width: (frames.values.map(\.maxX).max() ?? 0) + 400,
               height: (frames.values.map(\.maxY).max() ?? 0) + 400)
    }

    private func linkGeometry(frames: [PersistentIdentifier: CGRect]) -> [BoardLinksLayer.Segment] {
        project.links.compactMap { link in
            guard !link.isHiddenByTheories, let from = link.from, let to = link.to,
                  let a = frames[from.persistentModelID], let b = frames[to.persistentModelID] else { return nil }
            let start = Self.edgePoint(of: a, toward: CGPoint(x: b.midX, y: b.midY))
            let end = Self.edgePoint(of: b, toward: CGPoint(x: a.midX, y: a.midY))
            let role = link.role
            var label = link.label.isEmpty ? (role == .related ? "" : role.label) : link.label
            if !link.note.isEmpty { label += label.isEmpty ? "✎" : " ✎" }
            let arrow = link.directed || [.parent, .child, .supports, .contradicts].contains(role)
            let outsideActive = activeTheory.map { theory in !link.hypotheses.contains { $0 === theory } } ?? false
            let opacity = link.isRefuted ? 0.35 : (outsideActive ? 0.3 : 1)
            return .init(start: start, end: end, color: Self.color(for: role).opacity(opacity),
                         dashed: role == .contradicts, arrow: arrow, label: label)
        }
    }

    /// Where the line from a card's center toward `point` leaves the card's rectangle.
    static func edgePoint(of rect: CGRect, toward point: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = point.x - center.x, dy = point.y - center.y
        guard dx != 0 || dy != 0 else { return center }
        let scaleX = dx == 0 ? CGFloat.infinity : (rect.width / 2) / abs(dx)
        let scaleY = dy == 0 ? CGFloat.infinity : (rect.height / 2) / abs(dy)
        let scale = min(scaleX, scaleY)
        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    static func color(for role: LinkRole) -> Color {
        switch role {
        case .supports: .green
        case .contradicts: .red
        case .spouse, .parent, .child: .blue
        case .related: .secondary
        }
    }

    /// The board point at the middle of the visible area, nudged so new cards don't stack exactly.
    private func newCardPoint() -> CGPoint {
        let nudge = Double(project.cards.count % 6) * 24
        return CGPoint(x: (viewport.width / 2 - app.boardPan.width) / app.boardZoom - 100 + nudge,
                       y: (viewport.height / 2 - app.boardPan.height) / app.boardZoom - 40 + nudge)
    }

    private func boardPoint(fromView point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - app.boardPan.width) / app.boardZoom, y: (point.y - app.boardPan.height) / app.boardZoom)
    }

    // MARK: Actions

    private var pinnedVisits: [Visit] {
        project.sessions.flatMap(\.visits)
            .filter { $0.mark == .pinned }
            .sorted { $0.visitedAt > $1.visitedAt }
    }

    private func add(_ kind: CardKind) {
        app.addCard(kind, at: newCardPoint(), in: project)
    }

    private func tap(_ card: BoardCard) {
        // Shift-click connects the selected card to the clicked one.
        if NSEvent.modifierFlags.contains(.shift), let selected = selectedCard, selected !== card {
            app.connect(selected, to: card)
        } else {
            app.selectedCardID = card.persistentModelID
        }
    }

    private func setZoom(_ value: CGFloat) {
        app.boardZoom = min(max(value, AppState.zoomRange.lowerBound), AppState.zoomRange.upperBound)
    }

    private func fitToView() {
        let frames = cardFrames.values
        guard let minX = frames.map(\.minX).min(), let minY = frames.map(\.minY).min(),
              let maxX = frames.map(\.maxX).max(), let maxY = frames.map(\.maxY).max(),
              viewport.width > 0, viewport.height > 0 else { return }
        let margin: CGFloat = 40
        let scale = min((viewport.width - margin * 2) / max(maxX - minX, 1),
                        (viewport.height - margin * 2) / max(maxY - minY, 1))
        setZoom(scale)
        app.boardPan = CGSize(width: margin - minX * app.boardZoom, height: margin - minY * app.boardZoom)
    }

    /// When the board opens scrolled away from every card (another project's pan, a fresh import), fit it.
    private func fitIfNothingVisible() {
        let visible = CGRect(x: -app.boardPan.width / app.boardZoom, y: -app.boardPan.height / app.boardZoom,
                             width: viewport.width / app.boardZoom, height: viewport.height / app.boardZoom)
        let frames = cardFrames.values
        if !frames.isEmpty, !frames.contains(where: { $0.intersects(visible) }) { fitToView() }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = panStart ?? app.boardPan
                panStart = start
                app.boardPan = CGSize(width: start.width + value.translation.width,
                                      height: start.height + value.translation.height)
            }
            .onEnded { _ in panStart = nil }
    }

    /// The unzoomed board area. Card drags are measured here: measured on the card itself, the
    /// translation would already be in zoomed board units, and dividing by the zoom again made cards
    /// drift away from the pointer whenever the board wasn't at 100%.
    static let viewportSpace = "boardViewport"

    // MARK: Connecting by dragging

    /// The handle shows on the hovered or selected card, and stays on the source while dragging.
    private func showsHandle(for id: PersistentIdentifier) -> Bool {
        if let draft = app.linkDraft { return draft.from == id }
        return id == hoveredCardID || id == hoveredHandleID || id == app.selectedCardID
    }

    /// The card under the pointer while a connection is being dragged (the topmost, as drawn).
    private func linkTarget(frames: [PersistentIdentifier: CGRect]) -> BoardCard? {
        guard let draft = app.linkDraft else { return nil }
        return visibleCards.last { card in
            card.persistentModelID != draft.from && frames[card.persistentModelID]?.contains(draft.point) == true
        }
    }

    private func linkDrag(from card: BoardCard) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.viewportSpace))
            .onChanged { value in
                app.linkDraft = LinkDraft(from: card.persistentModelID, point: boardPoint(fromView: value.location))
            }
            .onEnded { _ in
                if let target = linkTarget(frames: cardFrames) {
                    app.connect(card, to: target)
                    app.selectedCardID = card.persistentModelID  // shows the new connection, ready for a role
                }
                app.linkDraft = nil
            }
    }

    private func cardDrag(_ card: BoardCard) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.viewportSpace))
            .onChanged { value in
                dragOffsets[card.persistentModelID] = CGSize(width: value.translation.width / zoom,
                                                             height: value.translation.height / zoom)
            }
            .onEnded { value in
                card.x += value.translation.width / zoom
                card.y += value.translation.height / zoom
                dragOffsets[card.persistentModelID] = nil
                app.save()
            }
    }

    /// Pages dragged from the Timeline arrive as their URL strings.
    private func dropPages(_ items: [String], at location: CGPoint) -> Bool {
        var point = boardPoint(fromView: location)
        var added = false
        for item in items {
            let visit = pinnedVisits.first { $0.urlString == item }
                ?? project.sessions.flatMap(\.visits).first { $0.urlString == item }
            if let visit {
                app.addEvidenceCard(for: visit, at: point, in: project)
            } else if let url = URL(string: item), url.scheme?.hasPrefix("http") == true {
                let card = app.addCard(.evidence, at: point, in: project)
                card.urlString = item
                card.title = url.host() ?? item
            } else {
                continue
            }
            added = true
            point.x += 30
            point.y += 30
        }
        return added
    }

    private func importScapple() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "scap") ?? .xml]
        panel.message = "Choose a Scapple board to add to this project's board"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try app.importScapple(from: url, into: project)
            fitToView()
        } catch {
            importError = error.localizedDescription
        }
    }
}

/// Connection lines, drawn underneath the cards.
struct BoardLinksLayer: View {
    struct Segment {
        let start: CGPoint
        let end: CGPoint
        let color: Color
        let dashed: Bool
        let arrow: Bool
        let label: String
    }

    let links: [Segment]

    var body: some View {
        Canvas { context, _ in
            for link in links {
                var line = Path()
                line.move(to: link.start)
                line.addLine(to: link.end)
                context.stroke(line, with: .color(link.color),
                               style: StrokeStyle(lineWidth: 1.5, dash: link.dashed ? [6, 4] : []))
                if link.arrow {
                    let angle = atan2(link.end.y - link.start.y, link.end.x - link.start.x)
                    var head = Path()
                    head.move(to: link.end)
                    head.addLine(to: CGPoint(x: link.end.x - 10 * cos(angle - .pi / 7), y: link.end.y - 10 * sin(angle - .pi / 7)))
                    head.addLine(to: CGPoint(x: link.end.x - 10 * cos(angle + .pi / 7), y: link.end.y - 10 * sin(angle + .pi / 7)))
                    head.closeSubpath()
                    context.fill(head, with: .color(link.color))
                }
                if !link.label.isEmpty {
                    let middle = CGPoint(x: (link.start.x + link.end.x) / 2, y: (link.start.y + link.end.y) / 2)
                    let label = context.resolve(Text(link.label).font(.caption2).foregroundStyle(link.color))
                    let size = label.measure(in: CGSize(width: 200, height: 40))
                    let backing = CGRect(x: middle.x - size.width / 2 - 4, y: middle.y - size.height / 2 - 1,
                                         width: size.width + 8, height: size.height + 2)
                    context.fill(Path(roundedRect: backing, cornerRadius: 4),
                                 with: .color(Color(nsColor: .underPageBackgroundColor)))
                    context.draw(label, at: middle)
                }
            }
        }
    }
}

struct BoardCardView: View {
    let card: BoardCard
    let isSelected: Bool
    /// True while another theory is active and this card isn't part of it.
    var dimmed = false
    /// True when a board check involves this card.
    var hasIssue = false
    /// True while a connection is being dragged over this card.
    var isLinkTarget = false

    private var theories: [Hypothesis] {
        card.hypotheses.filter(\.isVisible).sorted { $0.createdAt < $1.createdAt }
    }

    /// Selection wins, then a question flag, then the card's first visible theory.
    private var border: (color: Color, width: CGFloat, dash: [CGFloat]) {
        if isLinkTarget { return (.accentColor, 4, []) }
        if isSelected { return (.accentColor, 2, []) }
        if card.flag == .question { return (.orange, 2, []) }
        if let theory = theories.first {
            return (AppState.theoryColor(theory), 2, theory.status == .open ? [5, 3] : [])
        }
        return (Color.primary.opacity(0.15), 1, [])
    }

    private var image: NSImage? {
        if let file = card.visit?.screenshotFile ?? card.imageFile { return ScreenshotStore.image(file) }
        return nil
    }

    private var tint: Color {
        if card.flag == .conflict { return .red.opacity(0.28) }
        if let hex = card.colorHex, let color = Color(hex: hex) { return color.opacity(0.35) }
        switch card.kind {
        case .person: return .blue.opacity(0.14)
        case .event: return .purple.opacity(0.14)
        case .evidence: return .gray.opacity(0.10)
        case .note: return .yellow.opacity(0.14)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: card.kind == .event ? 14 : 8)
        VStack(alignment: .leading, spacing: 4) {
            if card.kind != .note || !card.title.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: card.kind.symbol).font(.caption).foregroundStyle(.secondary)
                    Text(card.title.isEmpty ? card.displayName : card.title)
                        .font(card.kind == .person ? .headline : .callout.weight(.semibold))
                        .foregroundStyle(card.title.isEmpty ? .secondary : .primary)
                    Spacer(minLength: 0)
                    theoryDots
                    flagIcon
                }
            }
            let facts = [card.date, card.place].filter { !$0.isEmpty }.joined(separator: " · ")
            if !facts.isEmpty {
                Text(facts).font(.caption).foregroundStyle(.secondary)
            }
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if !card.details.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Text(card.details)
                        .font(card.kind == .note ? .callout : .caption)
                        .lineLimit(card.kind == .note ? 40 : 6)
                    if card.kind == .note && card.title.isEmpty {
                        Spacer(minLength: 0)
                        theoryDots
                        flagIcon
                    }
                }
            }
            if card.kind == .evidence, let host = URL(string: card.urlString)?.host() {
                Text(host).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                shape.fill(Color(nsColor: .controlBackgroundColor))
                shape.fill(tint)
            }
        }
        .overlay {
            shape.stroke(border.color, style: StrokeStyle(lineWidth: border.width, dash: border.dash))
        }
        .opacity(card.isRefuted ? 0.45 : (dimmed ? 0.3 : 1))
        .contentShape(shape)
    }

    @ViewBuilder
    private var theoryDots: some View {
        if !theories.isEmpty {
            HStack(spacing: 2) {
                ForEach(theories) { theory in
                    Circle().fill(AppState.theoryColor(theory)).frame(width: 7, height: 7)
                        .help(theory.title)
                }
            }
        }
    }

    @ViewBuilder
    private var flagIcon: some View {
        if hasIssue {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .help("A check found a contradiction involving this card")
        }
        switch card.flag {
        case .question: Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
        case .conflict: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .none: EmptyView()
        }
    }
}

/// Floating editor for the selected card: its fields, flag, and connections.
struct CardEditor: View {
    @Environment(AppState.self) private var app
    @Environment(AISettings.self) private var aiSettings
    @Bindable var card: BoardCard
    let project: ResearchProject

    private var connections: [(link: BoardLink, other: BoardCard, outgoing: Bool)] {
        card.outgoing.compactMap { link in link.to.map { (link, $0, true) } }
            + card.incoming.compactMap { link in link.from.map { (link, $0, false) } }
    }

    private var linkInDetails: URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let text = card.details
        return detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))?.url
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Kind", selection: Binding(get: { card.kind }, set: { card.kind = $0 })) {
                        ForEach(CardKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    Button { app.selectedCardID = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }

                if card.kind != .note {
                    TextField(card.kind == .person ? "Name" : "Title", text: $card.title)
                        .textFieldStyle(.roundedBorder)
                }
                if card.kind == .person {
                    Picker("Sex", selection: Binding(get: { card.sex }, set: { card.sex = $0 })) {
                        ForEach(Sex.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .help("Used for the family tree and to place parents as husband and wife in GEDCOM")
                }
                if card.kind == .person || card.kind == .event {
                    TextField(card.kind == .person ? "Born – died, e.g. 1861–1934" : "Date", text: $card.date)
                        .textFieldStyle(.roundedBorder)
                    TextField("Place", text: $card.place)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.kind == .note ? "Text" : "Notes").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $card.details)
                        .font(.callout)
                        .frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                }
                Picker("Flag", selection: Binding(get: { card.flag }, set: { card.flag = $0 })) {
                    ForEach(CardFlag.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if let url = URL(string: card.urlString), !card.urlString.isEmpty {
                    Button("Open Page", systemImage: "safari") { app.openInBrowser(url) }
                }
                if let url = linkInDetails {
                    Button("Open Link in Notes", systemImage: "link") { app.openInBrowser(url) }
                }
                if card.kind == .evidence || (card.kind == .note && !card.details.isEmpty) {
                    Button("Suggest Cards with AI", systemImage: "sparkles") {
                        app.suggestionRequest = SuggestionRequest(card: card)
                    }
                    .disabled(!aiSettings.hasAPIKey)
                    .help(aiSettings.hasAPIKey
                          ? "Read this record and propose the people, events and relationships it shows"
                          : "Add an Anthropic API key in Settings")
                }
                if let transcription = card.visit?.transcription, !transcription.isEmpty {
                    DisclosureGroup("Transcription") {
                        Text(transcription).font(.caption).textSelection(.enabled)
                    }
                    .font(.caption)
                }

                Divider()
                Text("Connections").font(.subheadline.bold())
                if connections.isEmpty {
                    Text("Shift-click another card to connect it, or use Connect To below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(connections, id: \.link.persistentModelID) { connection in
                    ConnectionRow(link: connection.link, other: connection.other, outgoing: connection.outgoing)
                }
                Menu("Connect To…") {
                    ForEach(project.cards.filter { $0 !== card }.sorted { $0.displayName < $1.displayName }) { other in
                        Button(other.displayName) { app.connect(card, to: other) }
                    }
                }
                .fixedSize()

                if !project.hypotheses.isEmpty {
                    Divider()
                    Text("Theories").font(.subheadline.bold())
                    ForEach(project.hypotheses.sorted { $0.createdAt < $1.createdAt }) { theory in
                        Toggle(isOn: Binding(get: { card.hypotheses.contains { $0 === theory } },
                                             set: { app.setMembership(card, in: theory, $0) })) {
                            HStack(spacing: 5) {
                                Circle().fill(AppState.theoryColor(theory)).frame(width: 8, height: 8)
                                Text(theory.title).lineLimit(1)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }

                Divider()
                Button("Delete Card", systemImage: "trash", role: .destructive) { app.delete(card) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
            }
            .padding(12)
        }
        .frame(width: 300)
        .frame(maxHeight: 560)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
        .shadow(radius: 8, y: 2)
    }
}

private struct ConnectionRow: View {
    @Environment(AppState.self) private var app
    @Bindable var link: BoardLink
    let other: BoardCard
    let outgoing: Bool
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row
            if editing {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Label on the line, e.g. father, witness", text: $link.label)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    TextEditor(text: $link.note)
                        .font(.caption)
                        .frame(height: 54)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
                        .overlay(alignment: .topLeading) {
                            if link.note.isEmpty {
                                Text("Note: why this connection, which record shows it…")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .padding(5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .padding(.leading, 18)
            } else if !link.note.isEmpty {
                Text(link.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 18)
                    .onTapGesture { editing = true }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 6) {
            Image(systemName: outgoing ? "arrow.right" : "arrow.left")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(outgoing ? "This card → \(other.displayName)" : "\(other.displayName) → this card")
            Picker("Role", selection: Binding(get: { link.role }, set: { link.role = $0 })) {
                ForEach(LinkRole.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Text(other.displayName)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onTapGesture { app.selectedCardID = other.persistentModelID }
            Button { editing.toggle() } label: {
                Image(systemName: link.note.isEmpty && link.label.isEmpty ? "square.and.pencil" : "note.text")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(editing ? Color.accentColor : .secondary)
            .help("Label and note for this connection")
            Button { app.delete(link) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove connection")
        }
    }
}

extension Color {
    /// "#RRGGBB" → Color.
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

/// The round handle on a card's edge; drag it onto another card to connect them. Sized against the
/// zoom so it stays the same size, and as easy to grab, on screen at any zoom.
private struct ConnectHandle: View {
    let zoom: CGFloat

    var body: some View {
        let side = 16 / zoom
        Circle()
            .fill(Color.accentColor)
            .overlay(Circle().stroke(.white, lineWidth: 2 / zoom))
            .overlay(Image(systemName: "plus").font(.system(size: 9 / zoom, weight: .bold)).foregroundStyle(.white))
            .frame(width: side, height: side)
            .contentShape(Circle().inset(by: -4 / zoom))
            .pointerStyle(.grabIdle)
            .help("Drag onto another card to connect them")
    }
}
