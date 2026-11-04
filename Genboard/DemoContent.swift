#if DEBUG
import AppKit
import SwiftData

/// Debug builds only: `-GenboardDemo YES` fills an in-memory store with a tidy, fictional research
/// project for website screenshots; `-GenboardDemoShot board|tree|browse` picks the view.
/// Every person in it is invented.
extension AppState {
    static var isDemo: Bool { UserDefaults.standard.bool(forKey: "GenboardDemo") }

    func buildDemo() {
        let project = ResearchProject(name: "Tremblay family")
        context.insert(project)

        // An earlier, closed session, so the "Last time" banner has something to say.
        let earlier = ResearchSession(goal: "Trace Émilie Tremblay's parents from her memorial", project: project)
        earlier.startedAt = .now.addingTimeInterval(-6 * 86_400)
        earlier.endedAt = earlier.startedAt.addingTimeInterval(2 * 3_600)
        earlier.summary = "The memorial and the FamilySearch tree both give Antoine Tremblay and Marguerite Gagnon as parents. WikiTree names a Joseph Tremblay instead, with no source. Next: the 1861 baptism at St-Hugues in the Drouin collection."
        earlier.openQuestions = "Is Joseph Tremblay a brother of Antoine, or a different family?"
        earlier.savedTabURLs = [Sites.all[0].url.absoluteString, Sites.all[3].url.absoluteString]
        context.insert(earlier)
        context.insert(TodoItem(text: "Find the 1861 St-Hugues baptism in Drouin", project: project, fromSessionGoal: earlier.goal))
        context.insert(TodoItem(text: "Check whether WikiTree's Joseph Tremblay cites any record", project: project, fromSessionGoal: earlier.goal))

        startSession(in: project, goal: "Confirm who Émilie Tremblay's father was")
        guard let session = activeSession else { return }
        let pages: [(String, String, VisitMark, String)] = [
            ("https://www.findagrave.com/", "Émilie Tremblay (1861–1934) – memorial", .pinned,
             "Memorial lists parents Antoine Tremblay and Marguerite Gagnon."),
            ("https://www.familysearch.org/", "Émilie Tremblay – family tree", .pinned,
             "Tree agrees with the memorial, but no source is attached for the father."),
            ("https://www.wikitree.com/", "Tremblay – WikiTree profile", .deadEnd,
             "Names Joseph Tremblay as father. No sources."),
            ("https://www.genealogiequebec.com/", "Baptême, St-Hugues, 1861 – Drouin", .pinned,
             "Émilie, daughter of Antoine Tremblay, farmer, and Marguerite Gagnon. Godfather Joseph Tremblay, uncle."),
        ]
        for (index, page) in pages.enumerated() {
            let visit = Visit(url: URL(string: page.0)!, title: page.1, session: session)
            visit.visitedAt = .now.addingTimeInterval(Double(index - pages.count) * 600)
            visit.mark = page.2
            visit.note = page.3
            context.insert(visit)
        }
        for minutes in [55.0, 48, 33, 21] {
            let visit = Visit(url: URL(string: "https://www.familysearch.org/search")!, title: "Search results", session: session)
            visit.visitedAt = .now.addingTimeInterval(-minutes * 60)
            context.insert(visit)
        }

        // The board.
        func person(_ name: String, _ dates: String, _ place: String, _ sex: Sex, _ x: Double, _ y: Double) -> BoardCard {
            let card = addCard(.person, at: CGPoint(x: x, y: y), in: project)
            card.title = name
            card.date = dates
            card.place = place
            card.sex = sex
            return card
        }
        func event(_ title: String, _ date: String, _ place: String, _ x: Double, _ y: Double) -> BoardCard {
            let card = addCard(.event, at: CGPoint(x: x, y: y), in: project)
            card.title = title
            card.date = date
            card.place = place
            return card
        }
        let antoine = person("Antoine Tremblay", "b. 1826", "St-Hugues", .male, 40, 40)
        let marguerite = person("Marguerite Gagnon", "b. ~1832", "St-Hugues", .female, 330, 40)
        let joseph = person("Joseph Tremblay", "b. 1829", "St-Hugues", .male, 650, 40)
        let marriage = event("Marriage", "20 novembre 1855", "St-Hugues", 40, 185)
        let emilie = person("Émilie Tremblay", "1861–1934", "Ste-Hélène-de-Bagot", .female, 330, 320)
        let henri = person("Henri Bouchard", "1858–1921", "Ste-Hélène-de-Bagot", .male, 650, 320)
        let lucien = person("Lucien Bouchard", "b. 1892", "Ste-Hélène-de-Bagot", .male, 490, 480)
        let burial = event("Burial", "1888", "Ste-Hélène", 120, 480)

        let baptism = addCard(.evidence, at: CGPoint(x: 940, y: 200), in: project)
        baptism.title = "Drouin: baptism, St-Hugues 1861"
        baptism.urlString = "https://www.genealogiequebec.com/"
        baptism.details = "Daughter of Antoine Tremblay and Marguerite Gagnon. Godfather: Joseph Tremblay, uncle."
        baptism.citation = "Baptism of Émilie Tremblay, 3 Feb 1861, St-Hugues parish register, f. 12"
        baptism.repository = "Drouin Collection, Généalogie Québec"
        baptism.sourceType = .original
        baptism.information = .primary
        let profile = addCard(.evidence, at: CGPoint(x: 940, y: 40), in: project)
        profile.title = "WikiTree profile"
        profile.urlString = "https://www.wikitree.com/"
        profile.details = "Gives Joseph as father; no sources."
        profile.sourceType = .authored
        profile.information = .undetermined
        let doubt = addCard(.note, at: CGPoint(x: 940, y: 400), in: project)
        doubt.details = "Joseph was the godfather (“oncle”), which may be how WikiTree confused the two brothers."
        doubt.flag = .question

        connect(antoine, to: marguerite, role: .spouse)
        connect(antoine, to: marriage)?.label = "époux"
        connect(marguerite, to: marriage)?.label = "épouse"
        connect(marguerite, to: emilie, role: .parent)
        connect(emilie, to: henri, role: .spouse)
        connect(emilie, to: lucien, role: .parent)
        connect(henri, to: lucien, role: .parent)
        connect(emilie, to: burial)

        // Two competing theories about the father.
        selectedCardID = antoine.persistentModelID
        let antoineTheory = addHypothesis(to: project, title: "Émilie's father is Antoine Tremblay")
        antoineTheory.statement = "The 1861 baptism names Antoine; the memorial and FamilySearch agree."
        antoineTheory.status = .supported
        connect(antoine, to: emilie, role: .parent)?.note = "1861 baptism, St-Hugues: “fille d'Antoine Tremblay, cultivateur”."
        connect(baptism, to: antoine, role: .supports)
        addTodo("Look for Antoine in the 1861 census", to: antoineTheory)
        activeHypothesisID = nil

        selectedCardID = joseph.persistentModelID
        let josephTheory = addHypothesis(to: project, title: "Émilie's father is Joseph Tremblay")
        josephTheory.statement = "Only WikiTree says so, without a source."
        connect(joseph, to: emilie, role: .parent)
        connect(profile, to: joseph, role: .supports)
        connect(doubt, to: joseph, role: .contradicts)
        activeHypothesisID = nil
        selectedCardID = nil
        save()

        let shot = UserDefaults.standard.string(forKey: "GenboardDemoShot") ?? "board"
        switch shot {
        case "link", "card":
            bannerDismissed = true
            mainMode = .board
            showInspector = false
            showSidebar = false
            boardZoom = 0.8
            boardPan = CGSize(width: 60, height: 40)
            if shot == "link" {
                selectedLinkID = antoine.outgoing.first { $0.to === emilie }?.persistentModelID
            } else {
                selectedCardID = baptism.persistentModelID
            }
        case "search":
            showSearch = true
        case "report":
            reportProject = project
            if let path = UserDefaults.standard.string(forKey: "GenboardDemoReportPDF") {
                try? ResearchReport(project: project).pdfData().write(to: URL(fileURLWithPath: path))
            }
        case "tree":
            bannerDismissed = true
            mainMode = .tree
            treeRootID = lucien.persistentModelID
            showSidebar = false
            showInspector = false
        case "browse":
            mainMode = .browse
            showSidebar = true
            showInspector = true
        default:
            bannerDismissed = true
            mainMode = .board
            showInspector = false
            showChecks = true
            boardZoom = 0.72
            boardPan = CGSize(width: 290, height: 56)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            NSApp.windows.first { $0.isVisible && $0.canBecomeMain }?
                .setFrame(NSRect(x: 80, y: 80, width: 1440, height: 900), display: true)
        }
    }
}
#endif
