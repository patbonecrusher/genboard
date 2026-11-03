import Foundation

struct BoardIssue: Identifiable {
    enum Kind { case contradiction, possibleDuplicate }
    let id = UUID()
    let kind: Kind
    let message: String
    let cards: [BoardCard]
}

/// Local consistency checks over the board: compares the years on person and event cards along
/// their connections. No AI involved, so they run on every change for free.
enum BoardChecks {
    enum EventKind { case birth, death, marriage, other }

    struct Life {
        var birth: Int?
        var death: Int?
    }

    static func run(_ project: ResearchProject) -> [BoardIssue] {
        let people = project.cards.filter { $0.kind == .person }
        var issues: [BoardIssue] = []

        for person in people {
            let name = person.displayName
            let stated = statedLife(person)
            let events = linkedCards(of: person).filter { $0.kind == .event }
            let eventYears = events.compactMap { event in firstYear(in: event.date).map { (event, $0, kind(of: event)) } }

            if let birth = stated.birth, let death = stated.death, birth > death {
                issues.append(.init(kind: .contradiction, message: "\(name): born \(birth) but died \(death).", cards: [person]))
            }

            // Birth: the stated year, else a linked baptism or birth event.
            let birth = stated.birth ?? eventYears.first { $0.2 == .birth }?.1
            if let statedBirth = stated.birth {
                for (event, year, eventKind) in eventYears where eventKind == .birth && abs(year - statedBirth) > 2 {
                    issues.append(.init(kind: .contradiction,
                                        message: "\(name): dates say born \(statedBirth), but \(event.displayName) is \(year).",
                                        cards: [person, event]))
                }
            }

            // Death: the stated year, else the earliest linked burial or death event.
            let deathEvents = eventYears.filter { $0.2 == .death }
            let death = stated.death ?? deathEvents.map(\.1).min()
            if let statedDeath = stated.death {
                for (event, year, _) in deathEvents where abs(year - statedDeath) > 1 {
                    issues.append(.init(kind: .contradiction,
                                        message: "\(name): dates say died \(statedDeath), but \(event.displayName) is \(year).",
                                        cards: [person, event]))
                }
            }

            for (event, year, eventKind) in eventYears {
                if let death, eventKind != .death, year > death + 1 {
                    issues.append(.init(kind: .contradiction,
                                        message: "\(name) appears in \(event.displayName) (\(year)), after their death (\(death)).",
                                        cards: [person, event]))
                }
                // Boards often hang a couple's children off their marriage, so marriage checks only
                // apply to people connected as a spouse.
                if eventKind == .marriage && !isSpouse(person, in: event) { continue }
                if let birth, eventKind != .birth, year < birth - 1 {
                    issues.append(.init(kind: .contradiction,
                                        message: "\(name) appears in \(event.displayName) (\(year)), before their birth (\(birth)).",
                                        cards: [person, event]))
                }
                if let birth, eventKind == .marriage, year >= birth, year - birth < 13 {
                    issues.append(.init(kind: .contradiction,
                                        message: "\(name) would be \(year - birth) at \(event.displayName) (\(year)).",
                                        cards: [person, event]))
                }
            }
        }

        // Parent and child ages.
        for link in project.links {
            guard let from = link.from, let to = link.to, from.kind == .person, to.kind == .person else { continue }
            let (parent, child): (BoardCard, BoardCard)
            switch link.role {
            case .parent: (parent, child) = (from, to)
            case .child: (parent, child) = (to, from)
            default: continue
            }
            let parentLife = statedLife(parent), childLife = statedLife(child)
            if let parentBirth = parentLife.birth, let childBirth = childLife.birth {
                let gap = childBirth - parentBirth
                if gap < 13 || gap > 70 {
                    issues.append(.init(kind: .contradiction,
                                        message: "\(parent.displayName) would be \(gap) at the birth of \(child.displayName) (\(childBirth)).",
                                        cards: [parent, child]))
                }
            }
            if let parentDeath = parentLife.death, let childBirth = childLife.birth, childBirth > parentDeath + 1 {
                issues.append(.init(kind: .contradiction,
                                    message: "\(child.displayName) born \(childBirth), after parent \(parent.displayName) died (\(parentDeath)).",
                                    cards: [parent, child]))
            }
        }

        // The same person entered twice: same name, compatible birth years, not yet connected.
        for (index, first) in people.enumerated() {
            for second in people.dropFirst(index + 1) {
                guard !first.title.isEmpty, normalized(first.title) == normalized(second.title) else { continue }
                let births = (statedLife(first).birth, statedLife(second).birth)
                if let a = births.0, let b = births.1, abs(a - b) > 2 { continue }
                let connected = first.outgoing.contains { $0.to === second } || first.incoming.contains { $0.from === second }
                guard !connected else { continue }
                issues.append(.init(kind: .possibleDuplicate,
                                    message: "Two cards for \(first.displayName): possibly the same person.",
                                    cards: [first, second]))
            }
        }
        return issues
    }

    // MARK: Parsing

    /// Years in "1861–1934", "b. 1826", "d. 1888", "14 janvier 1817", "~1862".
    static func years(in text: String) -> [Int] {
        text.matches(of: /\b(1[5-9]\d\d|20\d\d)\b/).compactMap { Int($0.output.1) }
    }

    static func firstYear(in text: String) -> Int? { years(in: text).first }

    /// Birth and death from a person card's date field.
    static func statedLife(_ person: BoardCard) -> Life {
        let text = person.date.lowercased()
        let found = years(in: text)
        guard !found.isEmpty else { return Life() }
        let deathMarker = text.contains("d.") || text.contains("†") || text.contains("died") || text.contains("décé")
        let birthMarker = text.contains("b.") || text.contains("born") || text.contains("né")
        if found.count >= 2 { return Life(birth: found[0], death: found[1]) }
        if deathMarker && !birthMarker { return Life(death: found[0]) }
        return Life(birth: found[0])
    }

    static func kind(of event: BoardCard) -> EventKind {
        let text = (event.title + " " + event.details).lowercased()
        if ["burial", "death", "died", "sépulture", "inhumation", "décès", "deces"].contains(where: text.contains) { return .death }
        if ["baptism", "birth", "baptême", "bapteme", "naissance"].contains(where: text.contains) { return .birth }
        if ["marriage", "mariage", "wedding"].contains(where: text.contains) { return .marriage }
        return .other
    }

    /// Connected to the event as a spouse: the "spouse of" role, or a label like groom, bride or époux.
    private static func isSpouse(_ person: BoardCard, in event: BoardCard) -> Bool {
        let links = person.outgoing.filter { $0.to === event } + person.incoming.filter { $0.from === event }
        return links.contains { link in
            let label = link.label.lowercased()
            return link.role == .spouse
                || ["spouse", "groom", "bride", "husband", "wife", "époux", "épouse", "epoux", "epouse"].contains(where: label.contains)
        }
    }

    private static func linkedCards(of card: BoardCard) -> [BoardCard] {
        card.outgoing.compactMap(\.to) + card.incoming.compactMap(\.from)
    }

    /// "Olivine  Girard" and "olivine girard" match; so do "Hélène" and "Helene".
    private static func normalized(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
