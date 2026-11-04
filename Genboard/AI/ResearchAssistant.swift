import Foundation
import Observation
import SwiftData

struct ChatLine: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    var detail: String = ""
}

@Observable
final class AssistantChat {
    var lines: [ChatLine] = []
    var turns: [AITurn] = []
    var isSending = false
    var error: String?
}

/// Cards the AI proposes from one record, for the researcher to review before anything is added.
struct CardSuggestions {
    struct Person: Identifiable {
        let id: String  // the model's ref, e.g. "p1"
        var name: String
        var dates: String
        var place: String
        var role: String
        var notes: String
        /// An existing person card the model matched, used instead of creating a duplicate.
        var existingCard: BoardCard?
        var include = true
    }

    struct Participant {
        let person: String
        let role: String
    }

    struct Event: Identifiable {
        let id: String
        var type: String
        var title: String
        var date: String
        var place: String
        var notes: String
        var participants: [Participant]
        var include = true
    }

    struct Relationship: Identifiable {
        let id = UUID()
        let from: String
        let to: String
        let role: LinkRole
        var include = true
    }

    var summary: String
    var people: [Person]
    var events: [Event]
    var relationships: [Relationship]

    func name(of ref: String) -> String {
        people.first { $0.id == ref }?.name ?? ref
    }
}

struct SummaryDraft {
    let whereLeftOff: String
    let nextSteps: [String]
    let openQuestions: [String]
}

extension AppState {

    func askAssistant(_ question: String, attachPageText: Bool, attachScreenshot: Bool) async {
        guard let session = activeSession else { return }
        let chat = self.chat
        chat.lines.append(ChatLine(role: .user, text: question))
        chat.isSending = true
        chat.error = nil
        defer { chat.isSending = false }

        // The context snapshot rides in each user turn rather than the system prompt, so the
        // conversation stays append-only (cache-friendly and safe for replayed thinking blocks).
        var text = "<research_context>\n\(ResearchContext.describe(session))</research_context>\n"
        var parts: [AIContentPart] = []
        if let tab = selectedTab, let url = tab.url {
            text += "\n<current_page title=\"\(tab.title)\" url=\"\(url.absoluteString)\">\n"
            if attachPageText {
                let pageText = await tab.evaluateString("document.body ? document.body.innerText : ''")
                text += ResearchContext.limitedPageText(pageText) + "\n"
            }
            text += "</current_page>\n"
            if attachScreenshot, let png = await tab.snapshotPNG(), let jpeg = ImageUtil.jpegForAPI(pngData: png) {
                parts.append(.jpeg(jpeg))
            }
        }
        text += "\nQuestion: \(question)"
        parts.append(.text(text))
        let turn = AITurn.user(parts)

        do {
            let model = aiSettings.chatModel
            let reply = try await aiSettings.provider(for: model).send(model: model, effort: aiSettings.effort, system: Prompts.assistant,
                                                  turns: chat.turns + [turn], jsonSchema: nil)
            chat.turns += [turn, reply.assistantTurn]
            let cost = record(reply.usage, model: model, in: session)
            chat.lines.append(ChatLine(role: .assistant, text: reply.text,
                                       detail: "\(ModelCatalog.model(model).name) · \(cost.formatted(.currency(code: "USD").precision(.fractionLength(3))))"))
        } catch {
            chat.error = error.localizedDescription
        }
    }

    func transcribe(_ visit: Visit) async {
        guard let file = visit.screenshotFile, let png = ScreenshotStore.data(file),
              let jpeg = ImageUtil.jpegForAPI(pngData: png) else { return }
        let id = visit.persistentModelID
        busyVisits.insert(id)
        defer { busyVisits.remove(id) }

        let prompt = """
        Page: \(visit.displayTitle)
        URL: \(visit.urlString)
        Researcher's note: \(visit.note.isEmpty ? "(none)" : visit.note)
        """
        do {
            let model = aiSettings.transcriptionModel
            let reply = try await aiSettings.provider(for: model).send(model: model, effort: aiSettings.effort, system: Prompts.transcription,
                                                  turns: [.user([.jpeg(jpeg), .text(prompt)])], jsonSchema: nil)
            visit.transcription = reply.text
            if let session = visit.session { record(reply.usage, model: model, in: session) }
            save()
        } catch {
            aiErrorMessage = error.localizedDescription
        }
    }

    func draftSummary() async throws -> SummaryDraft {
        guard let session = activeSession else { throw AIError.badResponse }
        let pages = session.sortedVisits.map { visit in
            let mark = switch visit.mark {
            case .pinned: "PINNED"
            case .deadEnd: "DEAD END"
            case .none: "visited"
            }
            var line = "- [\(mark)] \(visit.displayTitle) (\(visit.urlString))"
            if !visit.note.isEmpty { line += " — note: \(visit.note)" }
            return line
        }.joined(separator: "\n")
        let text = """
        <research_context>
        \(ResearchContext.describe(session))</research_context>

        <this_session_pages>
        \(pages)
        </this_session_pages>

        Draft the end-of-session note for this session.
        """
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "where_left_off": ["type": "string"],
                "next_steps": ["type": "array", "items": ["type": "string"]],
                "open_questions": ["type": "array", "items": ["type": "string"]],
            ],
            "required": ["where_left_off", "next_steps", "open_questions"],
            "additionalProperties": false,
        ]
        let model = aiSettings.summaryModel
        let reply = try await aiSettings.provider(for: model).send(model: model, effort: "low", system: Prompts.summary,
                                              turns: [.user([.text(text)])], jsonSchema: schema)
        record(reply.usage, model: model, in: session)
        guard let json = try JSONSerialization.jsonObject(with: Data(reply.text.utf8)) as? [String: Any] else {
            throw AIError.badResponse
        }
        return SummaryDraft(
            whereLeftOff: json["where_left_off"] as? String ?? "",
            nextSteps: json["next_steps"] as? [String] ?? [],
            openQuestions: json["open_questions"] as? [String] ?? []
        )
    }

    func suggestCards(from card: BoardCard) async throws -> CardSuggestions {
        guard let project = card.project else { throw AIError.badResponse }
        let candidates = project.cards.filter { $0.kind == .person && $0 !== card }

        var text = "Record: \(card.displayName)\n"
        if !card.urlString.isEmpty { text += "URL: \(card.urlString)\n" }
        if !card.details.isEmpty { text += "Researcher's notes: \(card.details)\n" }
        if let transcription = card.visit?.transcription, !transcription.isEmpty {
            text += "Transcription:\n\(transcription)\n"
        }
        if !candidates.isEmpty {
            text += "\nPeople already on the board:\n"
            for (index, person) in candidates.enumerated() {
                let facts = [person.date, person.place].filter { !$0.isEmpty }.joined(separator: ", ")
                text += "- c\(index): \(person.displayName)\(facts.isEmpty ? "" : " (\(facts))")\n"
            }
        }
        text += "\nExtract the people, events and relationships this record shows."

        var parts: [AIContentPart] = []
        if let file = card.visit?.screenshotFile ?? card.imageFile, let png = ScreenshotStore.data(file),
           let jpeg = ImageUtil.jpegForAPI(pngData: png) {
            parts.append(.jpeg(jpeg))
        }
        parts.append(.text(text))

        let model = aiSettings.transcriptionModel
        let reply = try await aiSettings.provider(for: model).send(model: model, effort: aiSettings.effort, system: Prompts.suggestCards,
                                              turns: [.user(parts)], jsonSchema: Self.suggestionSchema)
        if let session = card.visit?.session ?? activeSession { record(reply.usage, model: model, in: session) }
        guard let json = try JSONSerialization.jsonObject(with: Data(reply.text.utf8)) as? [String: Any] else {
            throw AIError.badResponse
        }

        func string(_ object: [String: Any], _ key: String) -> String {
            (object[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let people = (json["people"] as? [[String: Any]] ?? []).map { object in
            let match = string(object, "existing_card")
            let index = match.hasPrefix("c") ? Int(match.dropFirst()) : nil
            return CardSuggestions.Person(
                id: string(object, "ref"), name: string(object, "name"), dates: string(object, "dates"),
                place: string(object, "place"), role: string(object, "role"), notes: string(object, "notes"),
                existingCard: index.flatMap { candidates.indices.contains($0) ? candidates[$0] : nil })
        }
        let events = (json["events"] as? [[String: Any]] ?? []).map { object in
            CardSuggestions.Event(
                id: string(object, "ref"), type: string(object, "type"), title: string(object, "title"),
                date: string(object, "date"), place: string(object, "place"), notes: string(object, "notes"),
                participants: (object["participants"] as? [[String: Any]] ?? []).map {
                    CardSuggestions.Participant(person: string($0, "person"), role: string($0, "role"))
                })
        }
        let relationships = (json["relationships"] as? [[String: Any]] ?? []).compactMap { object -> CardSuggestions.Relationship? in
            guard let role = LinkRole(rawValue: string(object, "role")) else { return nil }
            return CardSuggestions.Relationship(from: string(object, "from"), to: string(object, "to"), role: role)
        }
        return CardSuggestions(summary: string(json, "summary"), people: people, events: events, relationships: relationships)
    }

    private static let suggestionSchema: [String: Any] = {
        let text: [String: Any] = ["type": "string"]
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": Array(properties.keys), "additionalProperties": false]
        }
        let person = object(["ref": text, "name": text, "dates": text, "place": text, "role": text, "notes": text,
                             "existing_card": text])
        let participant = object(["person": text, "role": text])
        let event = object(["ref": text, "type": text, "title": text, "date": text, "place": text, "notes": text,
                            "participants": ["type": "array", "items": participant]])
        let relationship = object(["from": text, "to": text,
                                   "role": ["type": "string", "enum": ["parent", "child", "spouse"]]])
        return object(["summary": text,
                       "people": ["type": "array", "items": person],
                       "events": ["type": "array", "items": event],
                       "relationships": ["type": "array", "items": relationship]])
    }()

    @discardableResult
    private func record(_ usage: AIUsage, model: String, in session: ResearchSession) -> Double {
        let cost = ModelCatalog.cost(model: model, usage: usage)
        session.aiInputTokens += usage.totalInput
        session.aiOutputTokens += usage.output
        session.aiCostUSD += cost
        return cost
    }
}

enum ResearchContext {
    static let pageTextLimit = 30_000

    static func limitedPageText(_ text: String) -> String {
        guard text.count > pageTextLimit else { return text }
        return String(text.prefix(pageTextLimit))
            + "\n[Page text truncated: showing the first \(pageTextLimit) of \(text.count) characters.]"
    }

    /// A plain-text snapshot of the project for the model: goal, earlier summaries, to-dos, pins, dead ends.
    static func describe(_ session: ResearchSession) -> String {
        var out = ""
        let project = session.project
        out += "Project: \(project?.name ?? "Untitled")\n"
        out += "Current session goal: \(session.goal)\n"

        let earlier = (project?.sortedSessions ?? []).filter { $0 !== session && !$0.isOpen }
        if !earlier.isEmpty {
            out += "\nEarlier sessions (newest first):\n"
            for s in earlier.prefix(10) {
                out += "- \(s.startedAt.formatted(date: .abbreviated, time: .omitted)) — goal: \(s.goal)\n"
                if !s.summary.isEmpty { out += "  Where they left off: \(s.summary)\n" }
                if !s.openQuestions.isEmpty { out += "  Open questions: \(s.openQuestions)\n" }
            }
        }

        if let todos = project?.openTodos, !todos.isEmpty {
            out += "\nOpen to-dos:\n" + todos.map { "- \($0.text)" }.joined(separator: "\n") + "\n"
        }

        let allVisits = (project?.sessions ?? []).flatMap(\.visits).sorted { $0.visitedAt < $1.visitedAt }
        let pins = allVisits.filter { $0.mark == .pinned }
        if !pins.isEmpty {
            out += "\nPinned pages (evidence the researcher flagged):\n"
            for pin in pins {
                out += "- \(pin.displayTitle) — \(pin.urlString)\n"
                if !pin.note.isEmpty { out += "  Why it matters: \(pin.note)\n" }
                if !pin.selectedText.isEmpty { out += "  Selected text: \(pin.selectedText)\n" }
                if !pin.transcription.isEmpty { out += "  Transcription:\n\(pin.transcription)\n" }
            }
        }

        if let cards = project?.cards, !cards.isEmpty {
            out += "\nResearch board (the researcher's working tree and theories):\n"
            for card in cards.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
                var line = "- [\(card.kind.label)] \(card.displayName)"
                let facts = [card.date, card.place].filter { !$0.isEmpty }.joined(separator: ", ")
                if !facts.isEmpty { line += " (\(facts))" }
                if card.flag != .none { line += " [\(card.flag.label.uppercased())]" }
                if card.kind != .note, !card.details.isEmpty { line += ": \(card.details)" }
                if card.kind == .note, card.details.contains("\n") { line += ": \(card.details)" }
                if !card.urlString.isEmpty { line += " <\(card.urlString)>" }
                if card.kind == .evidence {
                    if card.sourceType != .unknown || card.information != .unknown { line += " (source: \(card.evidenceRating))" }
                    if !card.citation.isEmpty { line += " Citation: \(card.citation)" }
                }
                out += line + "\n"
            }
            let links = project?.links ?? []
            if !links.isEmpty {
                out += "Board connections:\n"
                for link in links {
                    guard let from = link.from, let to = link.to else { continue }
                    let label = link.label.isEmpty ? link.role.label : link.label
                    out += "- \(from.displayName) — \(label) → \(to.displayName)"
                    out += link.note.isEmpty ? "\n" : " (note: \(link.note))\n"
                }
            }
        }

        if let theories = project?.hypotheses, !theories.isEmpty {
            out += "\nTheories being tested:\n"
            for theory in theories.sorted(by: { $0.createdAt < $1.createdAt }) {
                out += "- \"\(theory.title)\" [\(theory.status.label.uppercased())]\n"
                if !theory.statement.isEmpty { out += "  Reasoning: \(theory.statement)\n" }
                if !theory.cards.isEmpty {
                    out += "  Cards: " + theory.cards.map(\.displayName).joined(separator: "; ") + "\n"
                }
                func describe(_ card: BoardCard) -> String {
                    card.kind == .evidence ? "\(card.displayName) (\(card.evidenceRating))" : card.displayName
                }
                let supporting = theory.evidence(.supports).map(describe)
                let against = BoardCard.unique(theory.evidence(.contradicts) + theory.cards.filter { $0.flag == .conflict })
                    .map(describe)
                out += "  Weight of evidence: \(theory.strength.label.lowercased())\n"
                if !supporting.isEmpty { out += "  Evidence for: " + supporting.joined(separator: "; ") + "\n" }
                if !against.isEmpty { out += "  Evidence against: " + against.joined(separator: "; ") + "\n" }
                let todos = theory.todos.filter { !$0.done }.map(\.text)
                if !todos.isEmpty { out += "  To-dos: " + todos.joined(separator: "; ") + "\n" }
            }
        }

        let deadEnds = allVisits.filter { $0.mark == .deadEnd }
        if !deadEnds.isEmpty {
            out += "\nDead ends (already checked, nothing useful):\n"
            for visit in deadEnds {
                out += "- \(visit.displayTitle) — \(visit.urlString)"
                out += visit.note.isEmpty ? "\n" : " (\(visit.note))\n"
            }
        }
        return out
    }
}

enum Prompts {
    static let assistant = """
    You are a genealogy research assistant inside Genboard, a macOS research workbench. The researcher \
    works across FamilySearch, WikiTree, Find a Grave, and Drouin records (Généalogie Québec), often for \
    French-Canadian and New England families.

    Each user message begins with a <research_context> snapshot: the project, the current session goal, \
    pinned pages with the researcher's notes, dead ends, to-dos, and earlier session summaries. It may also \
    include the current page's text or a screenshot. Later snapshots supersede earlier ones.

    How to help:
    - Keep what a source says separate from what is concluded, and name the source (pin title or site) for each fact you use.
    - When sources disagree, for example a FamilySearch tree and WikiTree, lay out each version and say what evidence would settle it, usually an original record such as a Drouin parish entry.
    - When theories are listed, weigh each against its evidence for and against, say which the evidence favors and why, and what single record would best settle it.
    - Suggest concrete next searches: which site, record type, parish, years, and name variants (dit names, Latin or anglicized spellings).
    - Say plainly when something is uncertain or not supported by the context. Never invent records, dates, or IDs.
    - Be concise, and reply in the language the researcher writes in.
    """

    static let transcription = """
    You transcribe historical genealogical documents from screenshots, commonly French-Canadian Catholic \
    parish registers (baptêmes, mariages, sépultures), civil records, census pages, gravestones, and online \
    family-tree pages.

    Respond with these sections:
    1. Transcription: in the original language, preserving spelling and abbreviations. Mark unreadable words as [illegible] and uncertain readings as [word?].
    2. Translation: into English, if the original is not English.
    3. Facts: a bullet list of events (type, date, place) and every person named with their role (subject, father, mother, spouse, godparent, witness, officiant), including ages and occupations when given.
    4. Notes: uncertain readings or anything that looks inconsistent.

    If the screenshot is a tree or memorial page rather than an original record, skip sections 1 and 2 and \
    list the facts it shows, noting that it is a derivative source.
    """

    static let suggestCards = """
    You turn one genealogical record into cards for a research board. Use only what the record itself \
    states; don't add facts from outside knowledge.

    - people: everyone named, with their role in this record (subject, father, mother, spouse, godfather, \
    godmother, witness, officiant, or other). dates: as written, like "b. 1861", "d. 1934" or "1861–1934"; \
    when only an age is given, compute it and mark it approximate, e.g. age 10 in the 1871 census gives \
    "b. ~1861". Keep names in the record's spelling. If a person clearly matches one already on the board \
    (same name and compatible dates), set existing_card to that id, e.g. "c2"; otherwise "".
    - events: the record's events (baptism, marriage, burial, census, and so on) with title, date, place, \
    and participants (person refs with their role in the event).
    - relationships: parent, child or spouse links the record states, between person refs. For "parent", \
    from is the parent of to.
    - Use refs p1, p2… for people and e1, e2… for events. Leave unknown fields as "".
    - summary: one sentence describing the record.
    """

    static let summary = """
    You write end-of-session notes for a genealogist so they can resume research later. Use only the \
    material provided, and be specific: names, dates, places, and record IDs that appear in it. \
    where_left_off is 2 to 5 sentences on what was established and where the work stopped. next_steps are \
    concrete actions (which site, which record, which person). open_questions are unresolved questions or \
    conflicts between sources. Write in the language of the researcher's notes.
    """
}
