import Foundation

/// Writes the board's people, families, events and sources as GEDCOM 5.5.1, the format other
/// genealogy software (FamilySearch, Ancestry, Gramps, MacFamilyTree…) imports.
enum GedcomExporter {
    struct Result {
        let text: String
        let people: Int
        let families: Int
    }

    static func export(_ project: ResearchProject, now: Date = .now) -> Result {
        let graph = FamilyGraph(project: project, includeRefuted: false)
        var out = GedcomWriter()

        out.line(0, "HEAD")
        out.line(1, "SOUR", "GENBOARD")
        out.line(2, "NAME", "Genboard")
        out.line(2, "VERS", "0.1")
        out.line(1, "DATE", gedcomDay(now))
        out.line(1, "GEDC")
        out.line(2, "VERS", "5.5.1")
        out.line(2, "FORM", "LINEAGE-LINKED")
        out.line(1, "CHAR", "UTF-8")
        out.text(1, "NOTE", "Exported from the Genboard project “\(project.name)”. Refuted and hidden theories are not included.")

        let personIDs = Dictionary(uniqueKeysWithValues: graph.people.enumerated().map { (ObjectIdentifier($1), "@I\($0 + 1)@") })
        let families = buildFamilies(graph)

        // Evidence cards that support a person become source records.
        var sources: [BoardCard] = []
        func sourceID(_ card: BoardCard) -> String {
            if let index = sources.firstIndex(where: { $0 === card }) { return "@S\(index + 1)@" }
            sources.append(card)
            return "@S\(sources.count)@"
        }

        for person in graph.people {
            out.line(0, personIDs[ObjectIdentifier(person)]!, "INDI")
            out.line(1, "NAME", gedcomName(person.title.isEmpty ? person.displayName : person.title))
            out.line(1, "SEX", person.sex == .unknown ? "U" : person.sex.rawValue)

            let life = BoardChecks.statedLife(person)
            let events = linkedEvents(of: person)
            let baptism = events.first { BoardChecks.kind(of: $0) == .birth }
            let burial = events.first { BoardChecks.kind(of: $0) == .death }
            if let birth = life.birth {
                out.line(1, "BIRT")
                out.line(2, "DATE", approximate(person.date) ? "ABT \(birth)" : "\(birth)")
                if !person.place.isEmpty { out.line(2, "PLAC", person.place) }
            }
            if let baptism {
                let tag = baptism.title.lowercased().contains("birth") || baptism.title.lowercased().contains("naissance") ? "BIRT" : "BAPM"
                out.line(1, tag)
                if let date = gedcomDate(baptism.date) { out.line(2, "DATE", date) }
                if !baptism.place.isEmpty { out.line(2, "PLAC", baptism.place) }
            }
            if let death = life.death {
                out.line(1, "DEAT")
                out.line(2, "DATE", "\(death)")
            }
            if let burial {
                let isDeath = ["death", "décès", "deces", "died"].contains(where: burial.title.lowercased().contains)
                out.line(1, isDeath ? "DEAT" : "BURI")
                if let date = gedcomDate(burial.date) { out.line(2, "DATE", date) }
                if !burial.place.isEmpty { out.line(2, "PLAC", burial.place) }
            }
            if !person.details.isEmpty { out.text(1, "NOTE", person.details) }
            for theory in person.hypotheses where theory.status != .refuted {
                out.text(1, "NOTE", "Part of the theory “\(theory.title)” (\(theory.status.label.lowercased())).")
            }
            if graph.parents(of: person).count > 2 {
                out.text(1, "NOTE", "Competing parents on the board: "
                         + graph.parents(of: person).map(\.displayName).joined(separator: ", ") + ".")
            }
            for (index, family) in families.enumerated() {
                if family.spouses.contains(where: { $0 === person }) { out.line(1, "FAMS", "@F\(index + 1)@") }
                if family.children.contains(where: { $0 === person }) { out.line(1, "FAMC", "@F\(index + 1)@") }
            }
            for evidence in person.incoming.filter({ $0.role == .supports }).compactMap(\.from) where evidence.kind == .evidence {
                out.line(1, "SOUR", sourceID(evidence))
                if !evidence.citation.isEmpty { out.line(2, "PAGE", evidence.citation) }
                if let quality = quality(of: evidence) { out.line(2, "QUAY", "\(quality)") }
            }
        }

        for (index, family) in families.enumerated() {
            out.line(0, "@F\(index + 1)@", "FAM")
            let (husband, wife) = husbandAndWife(family.spouses)
            if let husband, let id = personIDs[ObjectIdentifier(husband)] { out.line(1, "HUSB", id) }
            if let wife, let id = personIDs[ObjectIdentifier(wife)] { out.line(1, "WIFE", id) }
            for child in family.children {
                if let id = personIDs[ObjectIdentifier(child)] { out.line(1, "CHIL", id) }
            }
            if let marriage = marriageEvent(of: family.spouses) {
                out.line(1, "MARR")
                if let date = gedcomDate(marriage.date) { out.line(2, "DATE", date) }
                if !marriage.place.isEmpty { out.line(2, "PLAC", marriage.place) }
            }
        }

        for (index, source) in sources.enumerated() {
            out.line(0, "@S\(index + 1)@", "SOUR")
            out.line(1, "TITL", source.title.isEmpty ? source.displayName : source.title)
            if !source.repository.isEmpty { out.line(1, "PUBL", source.repository) }
            if !source.urlString.isEmpty { out.line(1, "NOTE", source.urlString) }
            if source.sourceType != .unknown || source.information != .unknown {
                out.line(1, "NOTE", "Source: \(source.evidenceRating).")
            }
            if let transcription = source.visit?.transcription, !transcription.isEmpty {
                out.text(1, "TEXT", transcription)
            } else if !source.details.isEmpty {
                out.text(1, "TEXT", source.details)
            }
        }

        out.line(0, "TRLR")
        return Result(text: out.output, people: graph.people.count, families: families.count)
    }

    // MARK: Families

    private struct Family {
        var spouses: [BoardCard]
        var children: [BoardCard] = []
    }

    /// One family per set of parents (and per spouse pair without children). When a child has more
    /// than two parents on the board (competing theories), the first two are used.
    private static func buildFamilies(_ graph: FamilyGraph) -> [Family] {
        var families: [Family] = []
        func key(_ cards: [BoardCard]) -> Set<ObjectIdentifier> { Set(cards.map(ObjectIdentifier.init)) }

        for child in graph.people {
            let parents = Array(graph.parents(of: child).prefix(2))
            guard !parents.isEmpty else { continue }
            if let index = families.firstIndex(where: { key($0.spouses) == key(parents) }) {
                families[index].children.append(child)
            } else {
                families.append(Family(spouses: parents, children: [child]))
            }
        }
        for person in graph.people {
            for spouse in graph.spouses(of: person) {
                let pair = [person, spouse]
                if !families.contains(where: { key($0.spouses) == key(pair) }) {
                    families.append(Family(spouses: pair))
                }
            }
        }
        return families
    }

    private static func husbandAndWife(_ spouses: [BoardCard]) -> (BoardCard?, BoardCard?) {
        var husband = spouses.first { $0.sex == .male }
        var wife = spouses.first { $0.sex == .female && $0 !== husband }
        for person in spouses where person !== husband && person !== wife {
            if husband == nil { husband = person } else if wife == nil { wife = person }
        }
        return (husband, wife)
    }

    /// A marriage event connected to both spouses.
    private static func marriageEvent(of spouses: [BoardCard]) -> BoardCard? {
        guard spouses.count == 2 else { return nil }
        let first = linkedEvents(of: spouses[0]), second = linkedEvents(of: spouses[1])
        return first.first { event in BoardChecks.kind(of: event) == .marriage && second.contains { $0 === event } }
    }

    private static func linkedEvents(of person: BoardCard) -> [BoardCard] {
        (person.outgoing.compactMap(\.to) + person.incoming.compactMap(\.from))
            .filter { $0.kind == .event && !$0.isHiddenByTheories && !$0.isRefuted }
    }

    // MARK: Values

    /// GEDCOM's 0–3 certainty scale: 3 for an original record with primary information, down to 0
    /// for an authored work. Nil when the source isn't rated.
    static func quality(of card: BoardCard) -> Int? {
        switch (card.sourceType, card.information) {
        case (.unknown, .unknown): nil
        case (.authored, _): 0
        case (_, .secondary): 1
        case (.original, .primary): 3
        default: 2
        }
    }

    /// "Olivine Girard" → "Olivine /Girard/" (the last word taken as the surname).
    static func gedcomName(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count > 1 else { return parts.first.map { "/\($0)/" } ?? "" }
        return parts.dropLast().joined(separator: " ") + " /\(parts.last!)/"
    }

    private static func approximate(_ text: String) -> Bool {
        let text = text.lowercased()
        return ["~", "abt", "about", "vers", "circa", "ca.", "env."].contains(where: text.contains)
    }

    private static let months: [(String, [String])] = [
        ("JAN", ["janvier", "january", "janv", "jan"]), ("FEB", ["février", "fevrier", "february", "févr", "fevr", "feb", "fév"]),
        ("MAR", ["mars", "march", "mar"]), ("APR", ["avril", "april", "avr", "apr"]), ("MAY", ["mai", "may"]),
        ("JUN", ["juin", "june", "jun"]), ("JUL", ["juillet", "july", "juil", "jul"]),
        ("AUG", ["août", "aout", "august", "aug"]), ("SEP", ["septembre", "september", "sept", "sep"]),
        ("OCT", ["octobre", "october", "oct"]), ("NOV", ["novembre", "november", "nov"]),
        ("DEC", ["décembre", "decembre", "december", "déc", "dec"]),
    ]

    /// "14 janvier 1817" → "14 JAN 1817"; "Nov 1855" → "NOV 1855"; "~1862" → "ABT 1862".
    static func gedcomDate(_ text: String) -> String? {
        guard let year = BoardChecks.firstYear(in: text) else { return nil }
        let lower = text.lowercased()
        let prefix = approximate(lower) ? "ABT " : ""
        let words = lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard let monthIndex = words.firstIndex(where: { word in months.contains { $0.1.contains(word) } }),
              let month = months.first(where: { $0.1.contains(words[monthIndex]) })?.0 else {
            return prefix + "\(year)"
        }
        if monthIndex > 0, let day = Int(words[monthIndex - 1]), (1...31).contains(day) {
            return prefix + "\(day) \(month) \(year)"
        }
        return prefix + "\(month) \(year)"
    }

    private static func gedcomDay(_ date: Date) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.day, .month, .year], from: date)
        return "\(parts.day ?? 1) \(months[(parts.month ?? 1) - 1].0) \(parts.year ?? 2026)"
    }
}

/// Accumulates GEDCOM lines, splitting multi-line and long text into CONT and CONC lines.
private struct GedcomWriter {
    private(set) var output = ""

    mutating func line(_ level: Int, _ tag: String, _ value: String = "") {
        let clean = value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: "")
        output += value.isEmpty ? "\(level) \(tag)\n" : "\(level) \(tag) \(clean)\n"
    }

    /// Free text: each paragraph after the first is a CONT line; pieces over 200 characters go on CONC lines.
    mutating func text(_ level: Int, _ tag: String, _ value: String) {
        for (index, paragraph) in value.components(separatedBy: .newlines).enumerated() {
            let chunks = stride(from: 0, to: max(paragraph.count, 1), by: 200).map { start -> String in
                let from = paragraph.index(paragraph.startIndex, offsetBy: start)
                let to = paragraph.index(from, offsetBy: min(200, paragraph.count - start))
                return String(paragraph[from..<to])
            }
            for (chunkIndex, chunk) in chunks.enumerated() {
                let tagForChunk = index == 0 && chunkIndex == 0 ? tag : (chunkIndex == 0 ? "CONT" : "CONC")
                line(index == 0 && chunkIndex == 0 ? level : level + 1, tagForChunk, chunk)
            }
        }
    }
}
