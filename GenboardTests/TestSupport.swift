import Foundation
import SwiftData
@testable import Genboard

/// An in-memory store and a project to build boards in, without the app's AppState.
struct Board {
    let container: ModelContainer
    let project: ResearchProject
    var context: ModelContext { container.mainContext }

    init(_ name: String = "Test") {
        container = try! ModelContainer(
            for: ResearchProject.self, ResearchSession.self, Visit.self, TodoItem.self,
            BoardCard.self, BoardLink.self, Hypothesis.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        project = ResearchProject(name: name)
        container.mainContext.insert(project)
    }

    @discardableResult
    func person(_ name: String, _ dates: String = "", sex: Sex = .unknown, place: String = "") -> BoardCard {
        let card = BoardCard(kind: .person, title: name, x: 0, y: 0, project: project)
        card.date = dates
        card.sex = sex
        card.place = place
        context.insert(card)
        return card
    }

    @discardableResult
    func card(_ kind: CardKind, _ title: String, date: String = "", details: String = "") -> BoardCard {
        let card = BoardCard(kind: kind, title: title, x: 0, y: 0, project: project)
        card.date = date
        card.details = details
        context.insert(card)
        return card
    }

    @discardableResult
    func link(_ from: BoardCard, _ to: BoardCard, _ role: LinkRole = .related, label: String = "") -> BoardLink {
        let link = BoardLink(from: from, to: to, role: role, project: project)
        link.label = label
        context.insert(link)
        return link
    }

    @discardableResult
    func theory(_ title: String, cards: [BoardCard], status: HypothesisStatus = .open) -> Hypothesis {
        let theory = Hypothesis(title: title, colorIndex: project.hypotheses.count, project: project)
        theory.status = status
        context.insert(theory)
        for card in cards { card.hypotheses.append(theory) }
        return theory
    }

    func save() { try! context.save() }
}

enum Fixtures {
    static func data(_ text: String) -> Data { Data(text.utf8) }
}
