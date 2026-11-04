import Foundation

/// Searches everything written down in every project: pages and their notes, transcriptions,
/// cards, citations, connection notes, theories, session summaries and to-dos. Case and accents
/// don't matter, and every word of the query has to appear.
enum ResearchSearch {
    enum Target {
        case visit(Visit)
        case card(BoardCard)
        case link(BoardLink)
        case theory(Hypothesis)
        case session(ResearchSession)
        case todo(TodoItem)
    }

    struct Hit: Identifiable {
        let id = UUID()
        let target: Target
        let project: ResearchProject
        let title: String
        let snippet: String

        var kind: String {
            switch target {
            case .visit(let visit): visit.mark == .pinned ? "Pinned page" : (visit.mark == .deadEnd ? "Dead end" : "Page")
            case .card(let card): card.kind.label
            case .link: "Connection"
            case .theory: "Theory"
            case .session: "Session"
            case .todo: "To-do"
            }
        }

        var symbol: String {
            switch target {
            case .visit(let visit): visit.mark == .pinned ? "pin.fill" : (visit.mark == .deadEnd ? "xmark.octagon" : "globe")
            case .card(let card): card.kind.symbol
            case .link: "line.diagonal"
            case .theory: "lightbulb"
            case .session: "clock"
            case .todo: "checklist"
            }
        }
    }

    static func search(_ query: String, in projects: [ResearchProject], limit: Int = 200) -> [Hit] {
        let terms = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        var hits: [Hit] = []

        func consider(_ target: Target, project: ResearchProject, title: String, fields: [String]) {
            guard hits.count < limit else { return }
            let normalized = fields.map(normalize)
            let all = normalized.joined(separator: "\n")
            guard terms.allSatisfy(all.contains) else { return }
            // The snippet comes from the first field after the title that mentions a term, else the title.
            let field = zip(fields, normalized).dropFirst().first { _, text in terms.contains(where: text.contains) }
            let snippet = field.map { snippetAround(terms, in: $0.0) } ?? ""
            hits.append(Hit(target: target, project: project, title: title, snippet: snippet))
        }

        for project in projects {
            for theory in project.hypotheses {
                consider(.theory(theory), project: project, title: theory.title, fields: [theory.title, theory.statement])
            }
            for card in project.cards {
                consider(.card(card), project: project, title: card.displayName,
                         fields: [card.displayName, card.title, card.details, card.date, card.place, card.citation, card.repository])
            }
            for link in project.links where !link.note.isEmpty || !link.label.isEmpty {
                guard let from = link.from, let to = link.to else { continue }
                consider(.link(link), project: project, title: "\(from.displayName) → \(to.displayName)",
                         fields: ["\(from.displayName) \(to.displayName)", link.label, link.note])
            }
            for session in project.sessions {
                consider(.session(session), project: project, title: session.goal,
                         fields: [session.goal, session.summary, session.openQuestions])
                for visit in session.visits {
                    consider(.visit(visit), project: project, title: visit.displayTitle,
                             fields: [visit.displayTitle, visit.note, visit.selectedText, visit.transcription, visit.urlString])
                }
            }
            for todo in project.todos {
                consider(.todo(todo), project: project, title: todo.text, fields: [todo.text])
            }
        }
        // Pinned pages, theories and cards first: the things the researcher wrote about.
        return hits.sorted { rank($0) < rank($1) }
    }

    private static func rank(_ hit: Hit) -> Int {
        switch hit.target {
        case .theory: 0
        case .card: 1
        case .visit(let visit): visit.mark == .pinned ? 1 : (visit.mark == .deadEnd ? 3 : 4)
        case .link: 2
        case .session: 2
        case .todo: 3
        }
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// About 120 characters of `text` around the first query term, on one line.
    static func snippetAround(_ terms: [String], in text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let normalized = normalize(flat)
        guard let match = terms.compactMap({ normalized.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return String(flat.prefix(120))
        }
        // Folding keeps the length of most Latin text the same, so offsets carry over.
        let offset = normalized.distance(from: normalized.startIndex, to: match.lowerBound)
        let start = max(0, offset - 40)
        let characters = Array(flat)
        guard start < characters.count else { return String(flat.prefix(120)) }
        let end = min(characters.count, start + 120)
        return (start > 0 ? "…" : "") + String(characters[start..<end]) + (end < characters.count ? "…" : "")
    }
}
