import Foundation
import PDFKit
import Testing
@testable import Genboard

@MainActor
struct ReportTests {
    /// Two competing fathers, one backed by a rated parish record.
    private func tremblayBoard() -> (Board, Hypothesis) {
        let board = Board("Tremblay family")
        let antoine = board.person("Antoine Tremblay", "b. 1826", sex: .male)
        let joseph = board.person("Joseph Tremblay", "b. 1829", sex: .male)
        let emilie = board.person("Émilie Tremblay", "1861–1934", sex: .female)
        let link = board.link(antoine, emilie, .parent)
        link.note = "Named as father in the 1861 baptism."
        board.link(joseph, emilie, .parent)
        let baptism = board.card(.evidence, "Drouin: baptism 1861")
        baptism.citation = "Baptism of Émilie Tremblay, 3 Feb 1861, St-Hugues, f. 12"
        baptism.repository = "Drouin Collection"
        baptism.sourceType = .original
        baptism.information = .primary
        board.link(baptism, antoine, .supports)
        let antoineTheory = board.theory("Émilie's father is Antoine", cards: [antoine, emilie], status: .supported)
        antoineTheory.statement = "The baptism names Antoine."
        link.hypotheses.append(antoineTheory)
        let wikitree = board.card(.evidence, "WikiTree profile")
        wikitree.sourceType = .authored
        board.link(wikitree, joseph, .supports)
        board.theory("Émilie's father is Joseph", cards: [joseph])
        let session = ResearchSession(goal: "Find Émilie's father", project: board.project)
        session.summary = "The baptism settles it."
        board.context.insert(session)
        let pin = Visit(url: URL(string: "https://www.genealogiequebec.com/")!, title: "Baptême 1861", session: session)
        pin.mark = .pinned
        pin.note = "Names Antoine."
        board.context.insert(pin)
        return (board, antoineTheory)
    }

    @Test func projectReportCoversTheoriesPeopleSourcesAndLog() {
        let (board, _) = tremblayBoard()
        let markdown = ResearchReport(project: board.project).markdown
        #expect(markdown.hasPrefix("# Tremblay family: research report"))
        #expect(markdown.contains("## Theories"))
        #expect(markdown.contains("### Émilie's father is Antoine"))
        #expect(markdown.contains("Status: Supported. Weight of evidence: fair (1 for)."))
        #expect(markdown.contains("- Drouin: baptism 1861 (Original · Primary). Baptism of Émilie Tremblay, 3 Feb 1861, St-Hugues, f. 12"))
        #expect(markdown.contains("Antoine Tremblay parent of Émilie Tremblay: Named as father in the 1861 baptism."))
        #expect(markdown.contains("Émilie Tremblay (1861–1934). Parents on the board: Antoine Tremblay, Joseph Tremblay"))
        #expect(markdown.contains("## Sources"))
        #expect(markdown.contains("Drouin Collection. Original · Primary"))
        #expect(markdown.contains("## Research log"))
        #expect(markdown.contains("- Baptême 1861. Names Antoine. https://www.genealogiequebec.com/"))
    }

    @Test func theoryReportOnlyCoversThatTheory() {
        let (board, theory) = tremblayBoard()
        let markdown = ResearchReport(project: board.project, scope: .theory(theory)).markdown
        #expect(markdown.hasPrefix("# Émilie's father is Antoine"))
        #expect(markdown.contains("Drouin Collection"))
        #expect(!markdown.contains("WikiTree"))
        #expect(!markdown.contains("Research log"))
    }

    @Test func htmlEscapesText() {
        let board = Board("<script> & co")
        let html = ResearchReport(project: board.project).html
        #expect(html.contains("&lt;script&gt; &amp; co"))
        #expect(!html.contains("<script>"))
    }

    @Test func pdfHasPages() throws {
        let (board, _) = tremblayBoard()
        let data = try ResearchReport(project: board.project).pdfData()
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount >= 1)
        #expect(document.string?.contains("Antoine Tremblay") == true)
    }
}

struct ReportTextTests {
    @Test func joinsSentencesWithoutDoublePeriods() {
        #expect(ResearchReport.sentences(["Baptême 1861", "Names Antoine.", "https://example.com/"]) == "Baptême 1861. Names Antoine. https://example.com/")
        #expect(ResearchReport.sentences(["One.", "", " Two. "]) == "One. Two.")
        #expect(ResearchReport.count(1, "theory", "theories") == "1 theory")
        #expect(ResearchReport.count(2, "theory", "theories") == "2 theories")
    }
}
