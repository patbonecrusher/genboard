import AppKit
import Foundation

/// A shareable write-up of a project or of one theory: the theories with their evidence for and
/// against, the people, the sources with their citations, and the research log. Built once as
/// blocks, then written out as Markdown, HTML or PDF.
struct ResearchReport {
    enum Block: Equatable {
        case heading(Int, String)
        case paragraph(String)
        /// A paragraph in small, muted type.
        case meta(String)
        case label(String)
        case bullets([String])
    }

    enum Scope {
        case project
        case theory(Hypothesis)
    }

    var title: String
    var blocks: [Block] = []

    // MARK: Building

    init(project: ResearchProject, scope: Scope = .project, now: Date = .now) {
        let dateLine = "Prepared with Genboard on \(now.formatted(date: .long, time: .omitted))."
        switch scope {
        case .project:
            title = "\(project.name): research report"
            blocks.append(.heading(1, title))
            blocks.append(.meta(dateLine))
            let people = project.cards.filter { $0.kind == .person && !$0.isRefuted }
            let sources = project.cards.filter { $0.kind == .evidence }
            blocks.append(.paragraph(Self.count(people.count, "person", "people") + ", "
                + Self.count(project.hypotheses.count, "theory", "theories") + ", "
                + Self.count(sources.count, "source", "sources") + " and "
                + Self.count(project.sessions.count, "research session", "research sessions") + "."))
            let theories = project.hypotheses.sorted { $0.createdAt < $1.createdAt }
            if !theories.isEmpty {
                blocks.append(.heading(2, "Theories"))
                theories.forEach { addTheory($0, level: 3) }
            }
            addPeople(people, project: project)
            addSources(sources)
            addLog(project)
            let todos = project.openTodos.map { todo in
                todo.hypothesis.map { "\(todo.text) (\($0.title))" } ?? todo.text
            }
            if !todos.isEmpty {
                blocks.append(.heading(2, "Still to do"))
                blocks.append(.bullets(todos))
            }
        case .theory(let theory):
            title = theory.title
            blocks.append(.heading(1, title))
            blocks.append(.meta("From the project “\(project.name)”. " + dateLine))
            addTheory(theory, level: 2, showsTitle: false)
            let people = theory.cards.filter { $0.kind == .person }
            addPeople(people, project: project)
            let sources = BoardCard.unique(theory.evidence(.supports) + theory.evidence(.contradicts)
                + theory.cards.filter { $0.kind == .evidence }).filter { $0.kind == .evidence }
            addSources(sources)
        }
    }

    private mutating func addTheory(_ theory: Hypothesis, level: Int, showsTitle: Bool = true) {
        let strength = theory.strength
        if showsTitle { blocks.append(.heading(level, theory.title)) }
        blocks.append(.meta("Status: \(theory.status.label). Weight of evidence: \(strength.label.lowercased()) (\(strength.counts))."))
        if !theory.statement.isEmpty { blocks.append(.paragraph(theory.statement)) }

        let supporting = theory.evidence(.supports)
        let against = BoardCard.unique(theory.evidence(.contradicts) + theory.cards.filter { $0.flag == .conflict })
        let questions = theory.cards.filter { $0.flag == .question }
        if !supporting.isEmpty {
            blocks.append(.label("Evidence for"))
            blocks.append(.bullets(supporting.map(Self.evidenceLine)))
        }
        if !against.isEmpty {
            blocks.append(.label("Evidence against"))
            blocks.append(.bullets(against.map(Self.evidenceLine)))
        }
        if !questions.isEmpty {
            blocks.append(.label("Open questions"))
            blocks.append(.bullets(questions.map { $0.kind == .note ? $0.details : $0.displayName }))
        }
        let reasoning = theory.links.filter { !$0.note.isEmpty }.compactMap { link -> String? in
            guard let from = link.from, let to = link.to else { return nil }
            return "\(from.displayName) \(link.label.isEmpty ? link.role.label : link.label) \(to.displayName): \(link.note)"
        }
        if !reasoning.isEmpty {
            blocks.append(.label("Connections"))
            blocks.append(.bullets(reasoning))
        }
        let todos = theory.todos.filter { !$0.done }.map(\.text)
        if !todos.isEmpty {
            blocks.append(.label("To do"))
            blocks.append(.bullets(todos))
        }
    }

    private mutating func addPeople(_ people: [BoardCard], project: ResearchProject) {
        guard !people.isEmpty else { return }
        let graph = FamilyGraph(project: project, includeRefuted: true)
        blocks.append(.heading(2, "People"))
        blocks.append(.bullets(people.sorted { $0.displayName < $1.displayName }.map { person in
            var line = person.displayName
            let facts = [person.date, person.place].filter { !$0.isEmpty }.joined(separator: ", ")
            if !facts.isEmpty { line += " (\(facts))" }
            let parents = graph.parents(of: person).map(\.displayName)
            let spouses = graph.spouses(of: person).map(\.displayName)
            if !parents.isEmpty { line += ". Parents on the board: " + parents.joined(separator: ", ") }
            if !spouses.isEmpty { line += ". Spouse: " + spouses.joined(separator: ", ") }
            return line
        }))
    }

    private mutating func addSources(_ sources: [BoardCard]) {
        guard !sources.isEmpty else { return }
        blocks.append(.heading(2, "Sources"))
        blocks.append(.bullets(sources.sorted { $0.displayName < $1.displayName }.map { source in
            var parts = [source.citation.isEmpty ? source.displayName : source.citation]
            if !source.repository.isEmpty { parts.append(source.repository) }
            parts.append(source.evidenceRating)
            if !source.urlString.isEmpty { parts.append(source.urlString) }
            return Self.sentences(parts)
        }))
    }

    private mutating func addLog(_ project: ResearchProject) {
        let sessions = project.sessions.sorted { $0.startedAt < $1.startedAt }
        guard !sessions.isEmpty else { return }
        blocks.append(.heading(2, "Research log"))
        for session in sessions {
            blocks.append(.heading(3, session.goal))
            blocks.append(.meta(session.startedAt.formatted(date: .long, time: .omitted)))
            if !session.summary.isEmpty { blocks.append(.paragraph(session.summary)) }
            if !session.openQuestions.isEmpty { blocks.append(.paragraph("Open questions: " + session.openQuestions)) }
            let pins = session.sortedVisits.filter { $0.mark == .pinned }
            if !pins.isEmpty {
                blocks.append(.label("Pinned pages"))
                blocks.append(.bullets(pins.map { pin in
                    Self.sentences([pin.displayTitle, pin.note, pin.urlString])
                }))
            }
            let deadEnds = session.sortedVisits.filter { $0.mark == .deadEnd }
            if !deadEnds.isEmpty {
                blocks.append(.label("Dead ends"))
                blocks.append(.bullets(deadEnds.map { [$0.displayTitle, $0.note].filter { !$0.isEmpty }.joined(separator: ": ") }))
            }
        }
    }

    /// Joins pieces as sentences without doubling the periods some of them already end with.
    static func sentences(_ parts: [String]) -> String {
        let pieces = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return pieces.enumerated().map { index, piece in
            index < pieces.count - 1 && piece.hasSuffix(".") ? String(piece.dropLast()) : piece
        }
        .joined(separator: ". ")
    }

    static func count(_ number: Int, _ singular: String, _ plural: String) -> String {
        "\(number) \(number == 1 ? singular : plural)"
    }

    private static func evidenceLine(_ card: BoardCard) -> String {
        switch card.kind {
        case .evidence: sentences(["\(card.displayName) (\(card.evidenceRating))", card.citation])
        case .note: card.details.isEmpty ? card.displayName : card.details
        case .person, .event: card.displayName
        }
    }

    // MARK: Writing

    var markdown: String {
        blocks.map { block in
            switch block {
            case .heading(let level, let text): String(repeating: "#", count: level) + " " + text
            case .paragraph(let text): text
            case .meta(let text): "*\(text)*"
            case .label(let text): "**\(text)**"
            case .bullets(let items): items.map { "- " + $0.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n")
            }
        }.joined(separator: "\n\n") + "\n"
    }

    var html: String { html(forPrint: false) }

    /// AppKit's HTML import draws list bullets twice, so the PDF gets bullets as indented paragraphs.
    private func html(forPrint: Bool) -> String {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
        }
        let body = blocks.map { block in
            switch block {
            case .heading(let level, let text): "<h\(level)>\(escape(text))</h\(level)>"
            case .paragraph(let text): "<p>\(escape(text))</p>"
            case .meta(let text): "<p class=\"meta\">\(escape(text))</p>"
            case .label(let text): "<p class=\"label\">\(escape(text))</p>"
            case .bullets(let items) where forPrint: items.map { "<p class=\"item\">•&nbsp;&nbsp;\(escape($0))</p>" }.joined()
            case .bullets(let items): "<ul>" + items.map { "<li>\(escape($0))</li>" }.joined() + "</ul>"
            }
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>\(escape(title))</title>
        <style>
        body { font: 11pt -apple-system, "Helvetica Neue", sans-serif; color: #1d1d1f; max-width: 46em; margin: 2em auto; line-height: 1.45; }
        h1 { font-size: 20pt; margin-bottom: 0.2em; }
        h2 { font-size: 14pt; margin-top: 1.6em; border-bottom: 1px solid #ddd; padding-bottom: 0.2em; }
        h3 { font-size: 12pt; margin-top: 1.2em; margin-bottom: 0.2em; }
        .meta { color: #6e6e73; font-size: 9.5pt; margin-top: 0; }
        .label { font-weight: 600; margin-bottom: 0.2em; }
        ul { margin-top: 0.2em; padding-left: 1.3em; }
        li { margin-bottom: 0.25em; }
        .item { margin: 0.15em 0 0.15em 1.2em; text-indent: -0.9em; }
        </style></head><body>
        \(body)
        </body></html>
        """
    }

    /// A paginated US Letter PDF, laid out by AppKit's text system.
    func pdfData() throws -> Data {
        guard let attributed = NSAttributedString(html: Data(html(forPrint: true).utf8), documentAttributes: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 612, height: 792)
        for side in [\NSPrintInfo.leftMargin, \.rightMargin] { printInfo[keyPath: side] = 54 }
        for side in [\NSPrintInfo.topMargin, \.bottomMargin] { printInfo[keyPath: side] = 54 }
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        textView.textStorage?.setAttributedString(attributed)
        textView.sizeToFit()

        let url = FileManager.default.temporaryDirectory.appending(path: "genboard-report-\(UUID()).pdf")
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else { throw CocoaError(.fileWriteUnknown) }
        defer { try? FileManager.default.removeItem(at: url) }
        return try Data(contentsOf: url)
    }
}
