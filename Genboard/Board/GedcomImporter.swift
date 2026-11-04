import Foundation

/// Reads the people and families of a GEDCOM file (5.5 / 5.5.1, as FamilySearch, Ancestry, Gramps
/// and MacFamilyTree write it) into plain values; `AppState.importGedcom` turns them into cards.
nonisolated enum GedcomImporter {
    struct Event: Equatable {
        var date = ""
        var place = ""
    }

    struct Person: Equatable {
        let id: String
        var name = ""
        var sex = Sex.unknown
        var birth: Event?
        /// Baptism or christening, used when there is no birth.
        var baptism: Event?
        var death: Event?
        var burial: Event?
        var notes: [String] = []
        var sourceIDs: [String] = []
    }

    struct Family: Equatable {
        let id: String
        var husband: String?
        var wife: String?
        var children: [String] = []
        var marriage: Event?
    }

    struct Result {
        var people: [Person] = []
        var families: [Family] = []
        /// Source titles by ID.
        var sources: [String: String] = [:]
    }

    enum ImportError: LocalizedError {
        case notGedcom
        var errorDescription: String? { "This doesn't look like a GEDCOM file: it has no people in it." }
    }

    /// One GEDCOM line: "1 BIRT", "2 DATE 14 JAN 1817", "0 @I1@ INDI".
    struct Line {
        let level: Int
        let xref: String?
        let tag: String
        var value: String
    }

    static func parse(_ data: Data) throws -> Result {
        // UTF-8 (with or without BOM) is what modern software writes; fall back to Latin-1 for old ANSEL-era files.
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let lines = joinContinuations(text.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) })

        var result = Result()
        var index = 0
        while index < lines.count {
            let record = lines[index]
            var end = index + 1
            while end < lines.count, lines[end].level > 0 { end += 1 }
            let body = Array(lines[(index + 1)..<end])
            if record.level == 0, let id = record.xref {
                switch record.tag {
                case "INDI": result.people.append(person(id: id, body))
                case "FAM": result.families.append(family(id: id, body))
                case "SOUR":
                    let title = body.first { $0.level == 1 && ($0.tag == "TITL" || $0.tag == "ABBR") }?.value
                    result.sources[id] = title ?? id
                default: break
                }
            }
            index = end
        }
        guard !result.people.isEmpty else { throw ImportError.notGedcom }
        return result
    }

    static func parseLine(_ raw: String) -> Line? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        var parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, let level = Int(parts[0]) else { return nil }
        var xref: String?
        if parts[1].hasPrefix("@") {
            let rest = parts[1].split(separator: " ", maxSplits: 1).map(String.init)
            xref = rest[0]
            parts[1] = rest.count > 1 ? rest[1] : ""
        }
        let tagAndValue = parts[1].split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let tag = tagAndValue.first, !tag.isEmpty else { return nil }
        return Line(level: level, xref: xref, tag: tag.uppercased(), value: tagAndValue.count > 1 ? tagAndValue[1] : "")
    }

    /// Folds CONT (new line) and CONC (same line) into the line they continue.
    private static func joinContinuations(_ lines: [Line]) -> [Line] {
        var out: [Line] = []
        for line in lines {
            if (line.tag == "CONT" || line.tag == "CONC"), !out.isEmpty {
                out[out.count - 1].value += (line.tag == "CONT" ? "\n" : "") + line.value
            } else {
                out.append(line)
            }
        }
        return out
    }

    private static func person(id: String, _ body: [Line]) -> Person {
        var person = Person(id: id)
        for (offset, line) in body.enumerated() where line.level == 1 {
            let children = subrecord(after: offset, in: body)
            switch line.tag {
            case "NAME" where person.name.isEmpty:
                let given = children.first { $0.tag == "GIVN" }?.value
                let surname = children.first { $0.tag == "SURN" }?.value
                person.name = displayName(line.value, given: given, surname: surname)
            case "SEX": person.sex = Sex(rawValue: line.value.prefix(1).uppercased()) ?? .unknown
            case "BIRT": person.birth = person.birth ?? event(children)
            case "BAPM", "CHR": person.baptism = person.baptism ?? event(children)
            case "DEAT": person.death = person.death ?? event(children)
            case "BURI": person.burial = person.burial ?? event(children)
            case "NOTE" where !line.value.hasPrefix("@"):
                if !line.value.isEmpty { person.notes.append(line.value) }
            case "SOUR" where line.value.hasPrefix("@"): person.sourceIDs.append(line.value)
            default: break
            }
        }
        return person
    }

    private static func family(id: String, _ body: [Line]) -> Family {
        var family = Family(id: id)
        for (offset, line) in body.enumerated() where line.level == 1 {
            switch line.tag {
            case "HUSB": family.husband = line.value
            case "WIFE": family.wife = line.value
            case "CHIL": family.children.append(line.value)
            case "MARR": family.marriage = event(subrecord(after: offset, in: body))
            default: break
            }
        }
        return family
    }

    /// The lines nested under the level-1 line at `offset`.
    private static func subrecord(after offset: Int, in body: [Line]) -> [Line] {
        Array(body[(offset + 1)...].prefix { $0.level > 1 })
    }

    private static func event(_ lines: [Line]) -> Event {
        Event(date: lines.first { $0.tag == "DATE" }?.value ?? "", place: lines.first { $0.tag == "PLAC" }?.value ?? "")
    }

    /// "Olivine /Girard/" → "Olivine Girard"; falls back to GIVN and SURN.
    static func displayName(_ value: String, given: String? = nil, surname: String? = nil) -> String {
        let name = value.replacingOccurrences(of: "/", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if !name.isEmpty { return name }
        return [given, surname].compactMap { $0 }.joined(separator: " ")
    }

    /// Life dates in the form the board's checks read: "1817–1880", "b. ~1862", "d. 1888".
    static func lifeDates(_ person: Person) -> String {
        func year(_ event: Event?) -> String? {
            guard let event, let year = BoardChecks.firstYear(in: event.date) else { return nil }
            let approximate = ["ABT", "EST", "CAL", "BEF", "AFT"].contains { event.date.uppercased().contains($0) }
            return (approximate ? "~" : "") + "\(year)"
        }
        let born = year(person.birth) ?? year(person.baptism)
        let died = year(person.death) ?? year(person.burial)
        switch (born, died) {
        case let (born?, died?): return "\(born)–\(died)"
        case let (born?, nil): return "b. \(born)"
        case let (nil, died?): return "d. \(died)"
        default: return ""
        }
    }

    /// Full dates and places, for the card's notes.
    static func details(_ person: Person, sources: [String: String]) -> String {
        var lines: [String] = []
        func add(_ label: String, _ event: Event?) {
            guard let event, !(event.date.isEmpty && event.place.isEmpty) else { return }
            lines.append("\(label) " + [event.date, event.place].filter { !$0.isEmpty }.joined(separator: ", "))
        }
        add("Born", person.birth)
        add("Baptized", person.baptism)
        add("Died", person.death)
        add("Buried", person.burial)
        lines += person.notes
        let titles = person.sourceIDs.compactMap { sources[$0] }
        if !titles.isEmpty { lines.append("Sources: " + titles.joined(separator: "; ")) }
        return lines.joined(separator: "\n")
    }

    /// Rows for a family-tree layout: everyone without known parents in the file starts at row 0,
    /// children go below their lowest parent, and spouses share a row.
    static func generations(_ result: Result) -> [String: Int] {
        var parents: [String: [String]] = [:]
        for family in result.families {
            for child in family.children {
                parents[child, default: []] += [family.husband, family.wife].compactMap { $0 }
            }
        }
        var row: [String: Int] = [:]
        func depth(_ id: String, _ visiting: Set<String>) -> Int {
            if let known = row[id] { return known }
            guard !visiting.contains(id) else { return 0 }  // a loop in a malformed file
            let value = (parents[id] ?? []).map { depth($0, visiting.union([id])) + 1 }.max() ?? 0
            row[id] = value
            return value
        }
        for person in result.people { _ = depth(person.id, []) }
        // Spouses share the deeper of their two rows; repeat so the change reaches their children.
        for _ in 0..<3 {
            for family in result.families {
                let spouses = [family.husband, family.wife].compactMap { $0 }
                let shared = spouses.compactMap { row[$0] }.max() ?? 0
                for spouse in spouses { row[spouse] = shared }
                for child in family.children { row[child] = max(row[child] ?? 0, shared + 1) }
            }
        }
        return row
    }
}
