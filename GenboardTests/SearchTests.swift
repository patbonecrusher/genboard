import Foundation
import Testing
@testable import Genboard

@MainActor
struct SearchTests {
    private func board() -> Board {
        let board = Board("Tremblay family")
        let emilie = board.person("Émilie Tremblay", "1861–1934", place: "Ste-Hélène-de-Bagot")
        let record = board.card(.evidence, "Drouin: baptism 1861")
        record.citation = "St-Hugues parish register, f. 12"
        let link = board.link(record, emilie, .supports)
        link.note = "Godfather Joseph Tremblay, oncle."
        board.theory("Émilie's father is Antoine", cards: [emilie])
        let session = ResearchSession(goal: "Find the 1861 baptism", project: board.project)
        session.summary = "Found it in the Drouin collection."
        board.context.insert(session)
        let visit = Visit(url: URL(string: "https://www.genealogiequebec.com/acte/1")!, title: "Baptême", session: session)
        visit.mark = .pinned
        visit.transcription = "Le trois février mil huit cent soixante et un, nous prêtre soussigné avons baptisé Émilie"
        board.context.insert(visit)
        board.context.insert(TodoItem(text: "Check the 1861 census", project: board.project, fromSessionGoal: ""))
        return board
    }

    @Test func ignoresCaseAndAccents() {
        let board = board()
        let hits = ResearchSearch.search("helene", in: [board.project])
        #expect(hits.map(\.title) == ["Émilie Tremblay"])
        #expect(ResearchSearch.search("EMILIE", in: [board.project]).count >= 3)
    }

    @Test func everyWordMustAppear() {
        let board = board()
        #expect(ResearchSearch.search("parish f. 12", in: [board.project]).map(\.title) == ["Drouin: baptism 1861"])
        #expect(ResearchSearch.search("parish Bagot", in: [board.project]).isEmpty)
    }

    @Test func findsTranscriptionsConnectionNotesSessionsAndTodos() {
        let board = board()
        let transcription = ResearchSearch.search("soixante", in: [board.project])
        #expect(transcription.map(\.kind) == ["Pinned page"])
        #expect(transcription[0].snippet.contains("soixante"))
        #expect(ResearchSearch.search("oncle", in: [board.project]).map(\.kind) == ["Connection"])
        #expect(ResearchSearch.search("drouin collection", in: [board.project]).map(\.kind) == ["Session"])
        #expect(ResearchSearch.search("census", in: [board.project]).map(\.kind) == ["To-do"])
    }

    @Test func theoriesComeFirst() {
        let board = board()
        let hits = ResearchSearch.search("antoine", in: [board.project])
        #expect(hits.first?.kind == "Theory")
    }

    @Test func emptyQueryFindsNothing() {
        #expect(ResearchSearch.search("   ", in: [board().project]).isEmpty)
    }

    @Test func snippetIsCenteredOnTheMatch() {
        let text = String(repeating: "a ", count: 100) + "needle" + String(repeating: " b", count: 100)
        let snippet = ResearchSearch.snippetAround(["needle"], in: text)
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.contains("needle"))
        #expect(snippet.count <= 122)
    }

    @Test func revealingACardSelectsItOnTheBoard() throws {
        let app = AppState()
        let project = ResearchProject(name: "Reveal")
        app.context.insert(project)
        app.startSession(in: project, goal: "Test")
        let card = app.addCard(.person, at: .zero, in: project)
        card.title = "Olivine Girard"
        app.selectedCardID = nil
        app.mainMode = .browse
        let hit = try #require(ResearchSearch.search("olivine", in: [project]).first)
        app.reveal(hit)
        #expect(app.mainMode == .board)
        #expect(app.selectedCardID == card.persistentModelID)
        #expect(app.boardFocusID == card.persistentModelID)
    }
}
