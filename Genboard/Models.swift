import Foundation
import SwiftData

@Model
final class ResearchProject {
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ResearchSession.project)
    var sessions: [ResearchSession] = []
    @Relationship(deleteRule: .cascade, inverse: \TodoItem.project)
    var todos: [TodoItem] = []
    @Relationship(deleteRule: .cascade, inverse: \BoardCard.project)
    var cards: [BoardCard] = []
    @Relationship(deleteRule: .cascade, inverse: \BoardLink.project)
    var links: [BoardLink] = []
    @Relationship(deleteRule: .cascade, inverse: \Hypothesis.project)
    var hypotheses: [Hypothesis] = []

    init(name: String) {
        self.name = name
        self.createdAt = .now
    }

    var sortedSessions: [ResearchSession] {
        sessions.sorted { $0.startedAt > $1.startedAt }
    }

    var openTodos: [TodoItem] {
        todos.filter { !$0.done }.sorted { $0.createdAt < $1.createdAt }
    }
}

@Model
final class ResearchSession {
    var goal: String
    var startedAt: Date
    var endedAt: Date?
    /// "Where I left off", written when the session is closed.
    var summary: String = ""
    var openQuestions: String = ""
    var summarySkipped: Bool = false
    var savedTabURLs: [String] = []
    var aiInputTokens: Int = 0
    var aiOutputTokens: Int = 0
    var aiCostUSD: Double = 0
    var project: ResearchProject?
    @Relationship(deleteRule: .cascade, inverse: \Visit.session)
    var visits: [Visit] = []

    init(goal: String, project: ResearchProject) {
        self.goal = goal
        self.startedAt = .now
        self.project = project
    }

    var isOpen: Bool { endedAt == nil }

    var sortedVisits: [Visit] {
        visits.sorted { $0.visitedAt < $1.visitedAt }
    }
}

enum VisitMark: String {
    case none, pinned, deadEnd
}

@Model
final class Visit {
    var urlString: String
    var title: String
    var visitedAt: Date
    var markRaw: String = VisitMark.none.rawValue
    /// Why this page matters (pins) or why it was a dead end.
    var note: String = ""
    var selectedText: String = ""
    var screenshotFile: String?
    var transcription: String = ""
    var session: ResearchSession?
    @Relationship(deleteRule: .nullify, inverse: \BoardCard.visit)
    var boardCards: [BoardCard] = []

    init(url: URL, title: String, session: ResearchSession) {
        self.urlString = url.absoluteString
        self.title = title
        self.visitedAt = .now
        self.session = session
    }

    var mark: VisitMark {
        get { VisitMark(rawValue: markRaw) ?? .none }
        set { markRaw = newValue.rawValue }
    }

    var url: URL? { URL(string: urlString) }

    var site: String {
        url?.host()?.replacingOccurrences(of: "www.", with: "") ?? urlString
    }

    var displayTitle: String { title.isEmpty ? site : title }
}

@Model
final class TodoItem {
    var text: String
    var done: Bool = false
    var createdAt: Date
    var fromSessionGoal: String = ""
    var project: ResearchProject?
    /// Set when the to-do was added to a theory on the board.
    var hypothesis: Hypothesis?

    init(text: String, project: ResearchProject?, fromSessionGoal: String) {
        self.text = text
        self.createdAt = .now
        self.project = project
        self.fromSessionGoal = fromSessionGoal
    }
}

// MARK: - Research board

nonisolated enum CardKind: String, CaseIterable, Identifiable {
    case person, event, evidence, note
    var id: String { rawValue }

    var label: String {
        switch self {
        case .person: "Person"
        case .event: "Event"
        case .evidence: "Evidence"
        case .note: "Note"
        }
    }

    var symbol: String {
        switch self {
        case .person: "person.fill"
        case .event: "calendar"
        case .evidence: "doc.text.image"
        case .note: "note.text"
        }
    }
}

nonisolated enum Sex: String, CaseIterable, Identifiable {
    case unknown = "", male = "M", female = "F"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .unknown: "Unknown"
        case .male: "Male"
        case .female: "Female"
        }
    }

    /// Guesses from a role in a record: father, mère, groom, godmother…
    static func from(role: String) -> Sex {
        let role = role.lowercased()
        if ["mother", "mère", "mere", "wife", "bride", "épouse", "epouse", "godmother", "marraine", "daughter", "fille", "widow", "veuve"]
            .contains(where: role.contains) { return .female }
        if ["father", "père", "pere", "husband", "groom", "époux", "epoux", "godfather", "parrain", "son", "fils", "widower", "veuf"]
            .contains(where: role.contains) { return .male }
        return .unknown
    }
}

nonisolated enum CardFlag: String, CaseIterable, Identifiable {
    case none, question, conflict
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .question: "Question"
        case .conflict: "Conflict"
        }
    }
}

/// What a connection means, read as "from <role> to": a parent link from A to B means A is B's parent.
nonisolated enum LinkRole: String, CaseIterable, Identifiable {
    case related, spouse, parent, child, supports, contradicts
    var id: String { rawValue }

    var label: String {
        switch self {
        case .related: "related"
        case .spouse: "spouse of"
        case .parent: "parent of"
        case .child: "child of"
        case .supports: "supports"
        case .contradicts: "contradicts"
        }
    }
}

@Model
final class BoardCard {
    var kindRaw: String
    /// Person name, event title, or evidence title. Notes keep their text in `details`.
    var title: String
    var details: String = ""
    /// Life dates for a person, the date for an event.
    var date: String = ""
    var place: String = ""
    var flagRaw: String = CardFlag.none.rawValue
    /// For people; GEDCOM needs it to place parents as husband and wife.
    var sexRaw: String = Sex.unknown.rawValue
    /// Top-left position and width in board coordinates.
    var x: Double
    var y: Double
    var width: Double
    /// Fill color carried over from an imported Scapple note, as "#RRGGBB".
    var colorHex: String?
    /// An image stored with ScreenshotStore (imported boards).
    var imageFile: String?
    /// The page an evidence card points to; kept even if the visit is deleted.
    var urlString: String = ""
    var createdAt: Date
    var project: ResearchProject?
    var visit: Visit?
    @Relationship(deleteRule: .cascade, inverse: \BoardLink.from)
    var outgoing: [BoardLink] = []
    @Relationship(deleteRule: .cascade, inverse: \BoardLink.to)
    var incoming: [BoardLink] = []
    var hypotheses: [Hypothesis] = []

    init(kind: CardKind, title: String = "", x: Double, y: Double, width: Double = 200, project: ResearchProject) {
        self.kindRaw = kind.rawValue
        self.title = title
        self.x = x
        self.y = y
        self.width = width
        self.createdAt = .now
        self.project = project
    }

    var kind: CardKind {
        get { CardKind(rawValue: kindRaw) ?? .note }
        set { kindRaw = newValue.rawValue }
    }

    var flag: CardFlag {
        get { CardFlag(rawValue: flagRaw) ?? .none }
        set { flagRaw = newValue.rawValue }
    }

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .unknown }
        set { sexRaw = newValue.rawValue }
    }

    /// A one-line name for menus, connection lists and the AI context.
    var displayName: String {
        let text = kind == .note ? details : title
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        if !firstLine.isEmpty { return String(firstLine.prefix(60)) }
        return kind == .evidence ? (URL(string: urlString)?.host() ?? "Evidence") : "Untitled \(kind.label.lowercased())"
    }
}

@Model
final class BoardLink {
    var roleRaw: String
    /// Short text drawn on the line, e.g. "father" or "witness"; replaces the role name when set.
    var label: String = ""
    /// The researcher's longer note about why the connection is there.
    var note: String = ""
    /// Draws an arrow toward `to`. Imported Scapple arrows set this; roles like "parent" imply it.
    var directed: Bool = false
    var from: BoardCard?
    var to: BoardCard?
    var project: ResearchProject?
    var hypotheses: [Hypothesis] = []

    init(from: BoardCard, to: BoardCard, role: LinkRole = .related, directed: Bool = false, project: ResearchProject) {
        self.roleRaw = role.rawValue
        self.from = from
        self.to = to
        self.directed = directed
        self.project = project
    }

    var role: LinkRole {
        get { LinkRole(rawValue: roleRaw) ?? .related }
        set { roleRaw = newValue.rawValue }
    }
}

nonisolated enum HypothesisStatus: String, CaseIterable, Identifiable {
    case open, supported, refuted
    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: "Open"
        case .supported: "Supported"
        case .refuted: "Refuted"
        }
    }

    var symbol: String {
        switch self {
        case .open: "circle.dashed"
        case .supported: "checkmark.circle.fill"
        case .refuted: "xmark.circle.fill"
        }
    }
}

/// A theory on the board, e.g. "Olivine's father is Pierre Girard": a status plus the cards and
/// connections that make it up. A card can belong to several competing theories.
@Model
final class Hypothesis {
    var title: String
    var statement: String = ""
    var statusRaw: String = HypothesisStatus.open.rawValue
    var colorIndex: Int
    var isVisible: Bool = true
    var createdAt: Date
    var project: ResearchProject?
    @Relationship(deleteRule: .nullify, inverse: \BoardCard.hypotheses)
    var cards: [BoardCard] = []
    @Relationship(deleteRule: .nullify, inverse: \BoardLink.hypotheses)
    var links: [BoardLink] = []
    @Relationship(deleteRule: .nullify, inverse: \TodoItem.hypothesis)
    var todos: [TodoItem] = []

    init(title: String, colorIndex: Int, project: ResearchProject) {
        self.title = title
        self.colorIndex = colorIndex
        self.createdAt = .now
        self.project = project
    }

    var status: HypothesisStatus {
        get { HypothesisStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    /// Cards connected to this theory's cards by a "supports" or "contradicts" link, each listed once
    /// even when it backs several cards in the theory.
    func evidence(_ role: LinkRole) -> [BoardCard] {
        let sources = cards.flatMap { member in member.incoming.filter { $0.role == role }.compactMap(\.from) }
        return BoardCard.unique(sources)
    }
}

extension BoardCard {
    /// Removes repeats, keeping the first occurrence of each card.
    static func unique(_ cards: [BoardCard]) -> [BoardCard] {
        var seen = Set<ObjectIdentifier>()
        return cards.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    /// Hidden when every theory it belongs to is hidden. Cards outside any theory always show.
    var isHiddenByTheories: Bool { !hypotheses.isEmpty && hypotheses.allSatisfy { !$0.isVisible } }
    /// Greyed out when every theory it belongs to has been refuted.
    var isRefuted: Bool { !hypotheses.isEmpty && hypotheses.allSatisfy { $0.status == .refuted } }
}

extension BoardLink {
    var isHiddenByTheories: Bool { !hypotheses.isEmpty && hypotheses.allSatisfy { !$0.isVisible } }
    var isRefuted: Bool { !hypotheses.isEmpty && hypotheses.allSatisfy { $0.status == .refuted } }
}
