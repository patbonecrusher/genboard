import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// What to do once the close-session sheet has been completed.
enum PendingAction {
    case activate(ResearchSession)
    case startNew(ResearchProject, goal: String)
    case quit
}

enum MainMode: Hashable {
    case browse, board, tree
}

/// A connection being dragged out of a card's handle; `point` is the pointer in board coordinates.
struct LinkDraft: Equatable {
    let from: PersistentIdentifier
    var point: CGPoint
}

/// A request to have the AI suggest cards from one record card; drives the review sheet.
struct SuggestionRequest: Identifiable {
    let id = UUID()
    let card: BoardCard
}

struct PinDraft: Identifiable {
    let id = UUID()
    let visit: Visit
    /// A fresh capture; nil when editing an existing pin's note.
    var screenshotPNG: Data?
    var selectedText: String
}

@Observable
final class AppState {
    let container: ModelContainer
    let aiSettings = AISettings()
    var context: ModelContext { container.mainContext }

    var activeSession: ResearchSession?
    var tabs: [BrowserTab] = []
    var selectedTabID: BrowserTab.ID?
    var showCloseSheet = false
    var pinDraft: PinDraft?
    var showInspector = true
    var showSidebar = true
    var mainMode = MainMode.browse
    var boardZoom: CGFloat = 1
    var boardPan = CGSize(width: 40, height: 40)
    var selectedCardID: PersistentIdentifier? {
        didSet { if selectedCardID != nil { selectedLinkID = nil } }
    }
    /// A connection clicked on the board; its editor replaces the card editor.
    var selectedLinkID: PersistentIdentifier? {
        didSet { if selectedLinkID != nil { selectedCardID = nil } }
    }
    var linkDraft: LinkDraft?
    /// The theory new cards and connections go into; other cards dim while one is active.
    var activeHypothesisID: PersistentIdentifier?
    var showTheories = true
    var showChecks = false
    var treeRootID: PersistentIdentifier?
    var treeShowsDescendants = false
    var treeGenerations = 4
    var suggestionRequest: SuggestionRequest?
    /// The project whose report sheet is showing.
    var reportProject: ResearchProject?
    var showSearch = false
    /// Result of a backup or restore, shown in an alert.
    var archiveMessage: String?
    /// Why a Scapple or GEDCOM import failed, shown in an alert.
    var boardImportError: String?
    /// Bumped after an import so the board fits everything into view.
    var boardFitRequest = 0
    /// A card the board should scroll to; BoardView centers it and clears this.
    var boardFocusID: PersistentIdentifier?
    /// A search result in another project, shown once that project's session is open.
    @ObservationIgnored private var pendingReveal: ResearchSearch.Hit?
    var bannerDismissed = false
    var chat = AssistantChat()
    var busyVisits: Set<PersistentIdentifier> = []
    var aiErrorMessage: String?
    /// Smoke test only: each tick moves keyboard focus into or out of the address bar.
    var stressFocusTick = 0
    @ObservationIgnored private var pendingAfterClose: PendingAction?
    @ObservationIgnored private var stressProject: ResearchProject?

    init() {
        if !Self.isSmokeTest && !Self.isRunningTests { BundleIDMigration.run() }
        do {
            // An explicit file: the unsandboxed default (Application Support/default.store) is shared
            // with every other unsandboxed SwiftData app on the Mac.
            let configuration = Self.isSmokeTest || Self.isRunningTests
                ? ModelConfiguration(isStoredInMemoryOnly: true)
                : ModelConfiguration(url: Self.storeURL)
            container = try ModelContainer(for: ResearchProject.self, ResearchSession.self, Visit.self, TodoItem.self,
                                           BoardCard.self, BoardLink.self, Hypothesis.self,
                                           configurations: configuration)
        } catch {
            fatalError("Could not open the Genboard store: \(error)")
        }
    }

    static let storeURL: URL = {
        #if DEBUG
        // Lets tests open a copy of a real store (e.g. to check a schema upgrade) instead of the live one.
        if let path = UserDefaults.standard.string(forKey: "GenboardStorePath") { return URL(fileURLWithPath: path) }
        #endif
        let directory = URL.applicationSupportDirectory.appending(path: "Genboard", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "Genboard.store")
    }()

    /// Unit tests run inside the app; they must never open the real store.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Debug launch with `-GenboardSmokeTest YES`: in-memory store and a session opened on a real page,
    /// so the full window (browser, inspector, banner) can be exercised without touching real data.
    static var isSmokeTest: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "GenboardSmokeTest") || isDemo
        #else
        false
        #endif
    }

    func startSmokeTestIfRequested() {
        guard Self.isSmokeTest, activeSession == nil else { return }
        #if DEBUG
        if Self.isDemo {
            buildDemo()
            return
        }
        #endif
        let project = ResearchProject(name: "Smoke Test")
        context.insert(project)
        let long = String(repeating: "Joseph Morel, son of Jean Morel and Marie Gagnon, baptized at Saint-Hyacinthe. ", count: 6)
        let earlier = ResearchSession(goal: "Earlier session with a long goal that wraps across several lines in the sidebar", project: project)
        earlier.summary = long
        earlier.openQuestions = long
        earlier.endedAt = .now
        earlier.savedTabURLs = [Sites.all[0].url.absoluteString]
        context.insert(earlier)
        for n in 1...4 {
            context.insert(TodoItem(text: "To-do \(n): \(long.prefix(120))", project: project, fromSessionGoal: earlier.goal))
        }
        createAndActivate(project: project, goal: "Smoke test session")
        if let session = activeSession {
            for n in 1...3 {
                let visit = Visit(url: URL(string: "https://www.wikitree.com/wiki/Test-\(n)")!, title: "Pinned page \(n)", session: session)
                visit.mark = n == 3 ? .deadEnd : .pinned
                visit.note = long
                context.insert(visit)
            }
        }
        selectedTab?.load(Sites.all[1].url)
        stressProject = project
        if let path = UserDefaults.standard.string(forKey: "GenboardSmokeImport") {
            let count = (try? importScapple(from: URL(fileURLWithPath: path), into: project)) ?? -1
            FileHandle.standardError.write(Data("Smoke import: \(count) notes, \(project.cards.count) cards, \(project.links.count) links\n".utf8))
        }
        if UserDefaults.standard.bool(forKey: "GenboardSmokeStill") {
            mainMode = .board  // a still board for screenshots, no stress timer
            let olivine = addCard(.person, at: CGPoint(x: 60, y: 520), in: project)
            olivine.title = "Olivine Girard"
            olivine.date = "1861–1934"
            olivine.place = "Ste-Hélène-de-Bagot"
            let adelard = addCard(.person, at: CGPoint(x: 360, y: 520), in: project)
            adelard.title = "Adélard Lapierre"
            let wedding = addCard(.event, at: CGPoint(x: 210, y: 680), in: project)
            wedding.title = "Marriage"
            wedding.date = "20 Nov 1855"
            wedding.place = "St-Hugues"
            let record = addCard(.evidence, at: CGPoint(x: 600, y: 600), in: project)
            record.title = "Drouin: burial of Olivine Girard"
            record.urlString = "https://www.genealogiequebec.com/"
            let doubt = addCard(.note, at: CGPoint(x: 60, y: 820), in: project)
            doubt.details = "Record says the father is Joseph Girard, not Pierre. Mother is Louise Brodeur."
            doubt.flag = .conflict
            connect(olivine, to: adelard, role: .spouse)
            connect(olivine, to: wedding)
            connect(record, to: olivine, role: .supports)
            connect(doubt, to: wedding, role: .contradicts)
            let pierre = addCard(.person, at: CGPoint(x: 60, y: 380), in: project)
            pierre.title = "Pierre Girard"
            pierre.date = "b. 1826"
            let joseph = addCard(.person, at: CGPoint(x: 360, y: 380), in: project)
            joseph.title = "Joseph Girard"
            selectedCardID = pierre.persistentModelID
            let pierreTheory = addHypothesis(to: project, title: "Olivine's father is Pierre Girard")
            connect(pierre, to: olivine, role: .parent)
            connect(record, to: pierre, role: .supports)
            activeHypothesisID = nil
            selectedCardID = joseph.persistentModelID
            let josephTheory = addHypothesis(to: project, title: "Olivine's father is Joseph Girard")
            connect(joseph, to: olivine, role: .parent)
            connect(doubt, to: joseph, role: .supports)
            josephTheory.status = .refuted
            addTodo("Check 1861 St-Hugues baptisms", to: pierreTheory)
            activeHypothesisID = pierreTheory.persistentModelID
            activeHypothesisID = nil
            let burial = addCard(.event, at: CGPoint(x: 600, y: 760), in: project)
            burial.title = "Burial"
            burial.date = "1888"
            burial.place = "Ste-Hélène"
            connect(olivine, to: burial)
            let olivineAgain = addCard(.person, at: CGPoint(x: 900, y: 520), in: project)
            olivineAgain.title = "Olivine  girard"
            olivineAgain.date = "b. ~1862"
            activeHypothesisID = pierreTheory.persistentModelID
            selectedCardID = nil
            showChecks = true
            // A marriage with a spouse who'd be 10: should be flagged, unlike the child linked to the 1855 marriage.
            let earlyMarriage = addCard(.event, at: CGPoint(x: 900, y: 680), in: project)
            earlyMarriage.title = "Mariage"
            earlyMarriage.date = "1871"
            connect(olivine, to: earlyMarriage)?.label = "épouse"
            for issue in BoardChecks.run(project) {
                FileHandle.standardError.write(Data("Check: \(issue.message)\n".utf8))
            }
            // A small family for the tree and GEDCOM.
            olivine.sex = .female
            adelard.sex = .male
            pierre.sex = .male
            joseph.sex = .male
            let marieLouise = addCard(.person, at: CGPoint(x: 1200, y: 380), in: project)
            marieLouise.title = "Marie-Louise Brodeur"
            marieLouise.date = "b. ~1832"
            marieLouise.sex = .female
            let elphege = addCard(.person, at: CGPoint(x: 1200, y: 520), in: project)
            elphege.title = "Elphège Lapierre"
            elphege.date = "b. 1892"
            elphege.place = "Ste-Hélène-de-Bagot"
            elphege.sex = .male
            activeHypothesisID = nil
            connect(marieLouise, to: olivine, role: .parent)
            connect(pierre, to: marieLouise, role: .spouse)
            connect(pierre, to: wedding)?.label = "époux"
            connect(marieLouise, to: wedding)?.label = "épouse"
            connect(olivine, to: elphege, role: .parent)
            connect(adelard, to: elphege, role: .parent)
            if UserDefaults.standard.bool(forKey: "GenboardSmokeTree") {
                mainMode = .tree
                treeRootID = elphege.persistentModelID
                showSidebar = false
                showInspector = false
            }
            if let path = UserDefaults.standard.string(forKey: "GenboardSmokeGedcom") {
                try? GedcomExporter.export(project).text.write(toFile: path, atomically: true, encoding: .utf8)
            }
            activeHypothesisID = pierreTheory.persistentModelID  // shows the theory editor in screenshots
            if let link = olivine.outgoing.first(where: { $0.to === elphege }) {
                link.note = "1892 baptism at Ste-Hélène names Olivine Girard as mother."
            }
            selectedCardID = olivine.persistentModelID
            if UserDefaults.standard.bool(forKey: "GenboardSmokeLinkDrag") {
                activeHypothesisID = nil
                selectedCardID = nil
                showSidebar = false
                showInspector = false
                showTheories = false
                showChecks = false
                linkDraft = LinkDraft(from: olivine.persistentModelID, point: CGPoint(x: adelard.x + 60, y: adelard.y + 20))
            }
            bannerDismissed = true
            boardZoom = 0.6
        } else {
            stressTest()
        }
    }

    /// Drives the window and the app's actions on a timer to shake out crashes: resizes, focus changes,
    /// panel toggles, page loads, tab churn, pins, dead ends, the close sheet, and session switches.
    private func stressTest() {
        var step = 0
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
                step += 1
                let width = [1000, 1180, 1420, 1050, 1600, 1100][step % 6]
                let height = [640, 900, 700, 1000, 660][step % 5]
                window.setFrame(NSRect(x: 100, y: 100, width: width, height: height), display: true)
                if step % 7 == 0 { self.showInspector.toggle() }
                if step % 11 == 0 { self.bannerDismissed.toggle() }
                if step % 23 == 0 { self.showSidebar.toggle() }
                if step % 2 == 0 { self.stressFocusTick += 1 }
                if step % 13 == 0 { self.selectedTab?.load(Sites.all[step % Sites.all.count].url) }
                if step % 17 == 0 { self.addTab(Sites.all[0].url) }
                if step % 19 == 0, self.tabs.count > 1, let tab = self.tabs.last { self.closeTab(tab) }

                // User actions, each as the matching button would trigger it.
                let currentStep = step
                let otherSession = self.stressProject?.sortedSessions.first { $0 !== self.activeSession }
                if step % 29 == 0, let otherSession { self.reopenTabs(of: otherSession) }
                if step % 31 == 0 { self.toggleDeadEnd() }
                if step % 37 == 0 {
                    self.beginPin()
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        if let draft = self.pinDraft { self.savePin(draft, note: "Stress pin \(currentStep)") }
                    }
                }
                if step % 43 == 0, let visit = self.activeSession?.sortedVisits.last(where: { $0.mark == .pinned }) {
                    self.openVisit(visit)
                    self.editPin(visit)
                    Task {
                        try? await Task.sleep(for: .seconds(0.6))
                        if let draft = self.pinDraft { self.savePin(draft, note: visit.note + " (edited)") }
                    }
                }
                if step % 47 == 0, self.pinDraft == nil {
                    self.requestEndSession()
                    Task {
                        try? await Task.sleep(for: .seconds(0.8))
                        self.cancelClose()
                    }
                }
                // Board actions.
                if let project = self.stressProject {
                    let cards = project.cards
                    if step % 27 == 0 { self.mainMode = self.mainMode == .board ? .browse : .board }
                    if step % 5 == 0, cards.count < 40 {
                        let card = self.addCard(CardKind.allCases[step % 4],
                                                at: CGPoint(x: Double(step * 37 % 1400), y: Double(step * 53 % 900)), in: project)
                        card.title = step % 4 == 3 ? "" : "Card \(step)"
                        card.details = step % 3 == 0 ? String(repeating: "Notes for card \(step). ", count: 8) : ""
                        card.flag = CardFlag.allCases[step % 3]
                    }
                    if step % 9 == 0, cards.count > 1 {
                        self.connect(cards[step % cards.count], to: cards[step * 7 % cards.count], role: LinkRole.allCases[step % 6])
                    }
                    if step % 8 == 0, !cards.isEmpty {
                        let card = cards[step % cards.count]
                        card.x += 40
                        card.y -= 20
                    }
                    if step % 10 == 0 {
                        self.boardZoom = [0.5, 1, 1.6, 0.8][step / 10 % 4]
                        self.boardPan = CGSize(width: Double(step % 200) - 100, height: Double(step % 150) - 50)
                    }
                    if step % 33 == 0, !cards.isEmpty { self.selectedCardID = cards[step % cards.count].persistentModelID }
                    if step % 35 == 0 { self.selectedCardID = nil }
                    if step % 61 == 0, let card = cards.first { self.delete(card) }
                    if step % 43 == 0, project.hypotheses.count < 5 { self.addHypothesis(to: project, title: "Theory \(step)") }
                    let theories = project.hypotheses
                    if step % 14 == 0, !theories.isEmpty { self.toggleActive(theories[step % theories.count]) }
                    if step % 16 == 0, !theories.isEmpty { theories[step % theories.count].isVisible.toggle() }
                    if step % 18 == 0, !theories.isEmpty {
                        theories[step % theories.count].status = HypothesisStatus.allCases[step % 3]
                    }
                    if step % 12 == 0, !theories.isEmpty, !cards.isEmpty {
                        self.setMembership(cards[step % cards.count], in: theories[step % theories.count], step % 24 != 0)
                    }
                    if step % 26 == 0, let theory = theories.first { self.addTodo("To-do \(step)", to: theory) }
                    if step % 97 == 0, let theory = theories.last { self.delete(theory) }
                    if step % 21 == 0 { self.showTheories.toggle() }
                    if step % 22 == 0 { self.showChecks.toggle() }
                    // A connection dragged from one card's handle and dropped on another.
                    if step % 15 == 0, cards.count > 1 {
                        let target = cards[step * 3 % cards.count]
                        self.linkDraft = LinkDraft(from: cards[step % cards.count].persistentModelID,
                                                   point: CGPoint(x: target.x + 10, y: target.y + 10))
                    }
                    if step % 15 == 7, let draft = self.linkDraft {
                        if let from = cards.first(where: { $0.persistentModelID == draft.from }),
                           let to = cards.first(where: { $0 !== from && CGRect(x: $0.x, y: $0.y, width: $0.width, height: 60).contains(draft.point) }) {
                            self.connect(from, to: to)
                        }
                        self.linkDraft = nil
                    }
                    if step % 39 == 0 { self.mainMode = .tree }
                    if step % 41 == 0, let person = cards.first(where: { $0.kind == .person }) {
                        self.treeRootID = person.persistentModelID
                        self.treeShowsDescendants.toggle()
                        self.treeGenerations = 2 + step % 8
                    }
                    if step % 57 == 0 { _ = GedcomExporter.export(project) }
                    if step % 53 == 0, let source = cards.first(where: { $0.kind == .evidence }) {
                        let suggestions = CardSuggestions(
                            summary: "Stress record",
                            people: [.init(id: "p1", name: "Stress Child \(step)", dates: "b. 1861", place: "St-Hugues",
                                           role: "subject", notes: ""),
                                     .init(id: "p2", name: "Stress Father \(step)", dates: "b. 1826", place: "",
                                           role: "father", notes: "", existingCard: cards.first { $0.kind == .person })],
                            events: [.init(id: "e1", type: "baptism", title: "", date: "1861", place: "St-Hugues", notes: "",
                                           participants: [.init(person: "p1", role: "subject"), .init(person: "p2", role: "father")])],
                            relationships: [.init(from: "p2", to: "p1", role: .parent)])
                        self.applySuggestions(suggestions, from: source)
                    }
                    if step % 71 == 0, let visit = project.sessions.flatMap(\.visits).first(where: { $0.mark == .pinned }) {
                        self.addEvidenceCard(for: visit, at: CGPoint(x: 200, y: 200), in: project)
                    }
                }
                if step % 89 == 0, self.pinDraft == nil, !self.showCloseSheet, let otherSession {
                    self.finishClose(summary: "Stress summary \(currentStep)", nextSteps: ["Stress step \(currentStep)"],
                                     openQuestions: "", keepTabs: true, skipped: false)
                    self.open(otherSession)
                }
            }
        }
    }

    var selectedTab: BrowserTab? { tabs.first { $0.id == selectedTabID } }
    var currentTabURLs: [String] { tabs.compactMap { $0.url?.absoluteString } }

    /// The session whose summary the "Last time" banner shows: the active session when it is being
    /// resumed, otherwise the most recently closed session of the same project.
    var lastTimeSession: ResearchSession? {
        guard let active = activeSession else { return nil }
        if !active.summary.isEmpty || active.summarySkipped { return active }
        return active.project?.sortedSessions.first { $0 !== active && !$0.isOpen }
    }

    func save() {
        try? context.save()
    }

    // MARK: - Sessions

    func startSession(in project: ResearchProject, goal: String) {
        if activeSession?.isOpen == true {
            pendingAfterClose = .startNew(project, goal: goal)
            showCloseSheet = true
            return
        }
        createAndActivate(project: project, goal: goal)
    }

    func open(_ session: ResearchSession) {
        guard session !== activeSession else { return }
        if activeSession?.isOpen == true {
            pendingAfterClose = .activate(session)
            showCloseSheet = true
            return
        }
        activate(session, restoreTabs: true)
    }

    func requestEndSession() {
        guard activeSession?.isOpen == true else { return }
        pendingAfterClose = nil
        showCloseSheet = true
    }

    func finishClose(summary: String, nextSteps: [String], openQuestions: String, keepTabs: Bool, skipped: Bool) {
        guard let session = activeSession else { return }
        session.summary = summary
        session.openQuestions = openQuestions
        session.summarySkipped = skipped
        session.savedTabURLs = keepTabs ? currentTabURLs : []
        for step in nextSteps {
            context.insert(TodoItem(text: step, project: session.project, fromSessionGoal: session.goal))
        }
        session.endedAt = .now
        showCloseSheet = false
        activeSession = nil
        tabs = []
        selectedTabID = nil
        save()

        let pending = pendingAfterClose
        pendingAfterClose = nil
        switch pending {
        case .activate(let next): activate(next, restoreTabs: true)
        case .startNew(let project, let goal): createAndActivate(project: project, goal: goal)
        case .quit: NSApp.reply(toApplicationShouldTerminate: true)
        case nil: break
        }
    }

    func cancelClose() {
        showCloseSheet = false
        pendingReveal = nil
        if case .quit = pendingAfterClose {
            NSApp.reply(toApplicationShouldTerminate: false)
        }
        pendingAfterClose = nil
    }

    func handleQuitRequest() -> NSApplication.TerminateReply {
        guard let session = activeSession, session.isOpen else {
            save()
            return .terminateNow
        }
        let hasWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        guard hasWindow else {
            // No window to show the prompt in: keep the tabs and flag the missing summary.
            session.savedTabURLs = currentTabURLs
            session.summarySkipped = session.summary.isEmpty
            session.endedAt = .now
            save()
            return .terminateNow
        }
        pendingAfterClose = .quit
        showCloseSheet = true
        return .terminateLater
    }

    func delete(_ session: ResearchSession) {
        if session === activeSession {
            activeSession = nil
            tabs = []
            selectedTabID = nil
        }
        session.visits.compactMap(\.screenshotFile).forEach(ScreenshotStore.delete)
        context.delete(session)
        save()
    }

    func delete(_ project: ResearchProject) {
        project.sessions.forEach(delete)
        context.delete(project)
        save()
    }

    private func createAndActivate(project: ResearchProject, goal: String) {
        let session = ResearchSession(goal: goal, project: project)
        context.insert(session)
        activate(session, restoreTabs: false)
    }

    private func activate(_ session: ResearchSession, restoreTabs: Bool) {
        session.endedAt = nil
        activeSession = session
        bannerDismissed = false
        chat = AssistantChat()
        tabs = []
        if restoreTabs {
            session.savedTabURLs.compactMap(URL.init(string:)).forEach { addTab($0, select: false) }
        }
        if tabs.isEmpty { addTab(nil, select: false) }
        selectedTabID = tabs.first?.id
        save()
        if let hit = pendingReveal, hit.project === session.project {
            pendingReveal = nil
            reveal(hit)
        }
    }

    // MARK: - Search

    /// Opens a search result where it lives: pages in the browser, cards, connections and theories
    /// on the board. A result in another project first opens that project's latest session.
    func reveal(_ hit: ResearchSearch.Hit) {
        if case .session(let session) = hit.target {
            open(session)
            return
        }
        guard activeSession?.project === hit.project else {
            guard let latest = hit.project.sortedSessions.first else { return }
            pendingReveal = hit
            open(latest)
            return
        }
        switch hit.target {
        case .visit(let visit):
            mainMode = .browse
            openVisit(visit)
        case .card(let card):
            if card.isHiddenByTheories { card.hypotheses.forEach { $0.isVisible = true } }
            mainMode = .board
            selectedCardID = card.persistentModelID
            boardFocusID = card.persistentModelID
        case .link(let link):
            mainMode = .board
            selectedLinkID = link.persistentModelID
            boardFocusID = link.from?.persistentModelID
        case .theory(let theory):
            mainMode = .board
            showTheories = true
            if activeHypothesisID != theory.persistentModelID { toggleActive(theory) }
        case .todo(let todo):
            if let theory = todo.hypothesis {
                mainMode = .board
                showTheories = true
                if activeHypothesisID != theory.persistentModelID { toggleActive(theory) }
            } else {
                showInspector = true
            }
        case .session:
            break
        }
    }

    // MARK: - Tabs

    @discardableResult
    func addTab(_ url: URL? = nil, select: Bool = true) -> BrowserTab {
        let tab = BrowserTab(url: url)
        tab.onURLChange = { [weak self] tab in self?.recordVisit(for: tab) }
        tab.onTitleChange = { [weak self] tab in self?.updateVisitTitle(for: tab) }
        tab.onOpenInNewTab = { [weak self] url in self?.addTab(url) }
        tabs.append(tab)
        if select { selectedTabID = tab.id }
        return tab
    }

    func newTab() {
        guard activeSession != nil else { return }
        addTab()
    }

    func closeTab(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty { addTab() }
        if selectedTabID == tab.id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    func reopenTabs(of session: ResearchSession) {
        let urls = session.savedTabURLs.compactMap(URL.init(string:))
        guard !urls.isEmpty else { return }
        // Empty start tabs are replaced by the reopened ones. Collected up front: new tabs have no
        // URL yet either, and `tabs` can't be read inside its own removeAll.
        let emptyTabIDs = Set(tabs.filter { $0.url == nil }.map(\.id))
        let reopened = urls.map { addTab($0, select: false) }
        tabs.removeAll { emptyTabIDs.contains($0.id) }
        if selectedTab == nil { selectedTabID = reopened.first?.id }
    }

    func openVisit(_ visit: Visit) {
        guard let url = visit.url else { return }
        if let tab = selectedTab {
            tab.load(url)
        } else {
            addTab(url)
        }
    }

    // MARK: - Visit history

    private func recordVisit(for tab: BrowserTab) {
        guard let session = activeSession, let url = tab.url,
              url.scheme == "http" || url.scheme == "https" else { return }
        if let last = tab.currentVisit, last.urlString == url.absoluteString { return }
        // Redirect chains fire several URL changes within a moment; keep only where they land.
        if let last = tab.currentVisit, last.mark == .none, Date.now.timeIntervalSince(last.visitedAt) < 2 {
            last.urlString = url.absoluteString
            last.title = tab.webView.title ?? ""
            return
        }
        let visit = Visit(url: url, title: tab.webView.title ?? "", session: session)
        context.insert(visit)
        tab.currentVisit = visit
    }

    private func updateVisitTitle(for tab: BrowserTab) {
        guard let visit = tab.currentVisit, visit.urlString == tab.url?.absoluteString,
              let title = tab.webView.title, !title.isEmpty else { return }
        visit.title = title
    }

    private func visitForCurrentPage(of tab: BrowserTab) -> Visit? {
        guard let url = tab.url else { return nil }
        if tab.currentVisit?.urlString != url.absoluteString { recordVisit(for: tab) }
        return tab.currentVisit
    }

    // MARK: - Pins and dead ends

    func beginPin() {
        guard let tab = selectedTab, let visit = visitForCurrentPage(of: tab) else { return }
        Task {
            let png = await tab.snapshotPNG()
            let selection = await tab.evaluateString("window.getSelection().toString()")
            pinDraft = PinDraft(visit: visit, screenshotPNG: png,
                                selectedText: selection.isEmpty ? visit.selectedText : selection)
        }
    }

    func editPin(_ visit: Visit) {
        pinDraft = PinDraft(visit: visit, screenshotPNG: nil, selectedText: visit.selectedText)
    }

    func savePin(_ draft: PinDraft, note: String) {
        let visit = draft.visit
        visit.mark = .pinned
        visit.note = note
        visit.selectedText = draft.selectedText
        if let png = draft.screenshotPNG, let file = ScreenshotStore.save(png) {
            if let old = visit.screenshotFile { ScreenshotStore.delete(old) }
            visit.screenshotFile = file
        }
        pinDraft = nil
        save()
    }

    func toggleDeadEnd() {
        guard let tab = selectedTab, let visit = visitForCurrentPage(of: tab) else { return }
        setMark(visit.mark == .deadEnd ? .none : .deadEnd, on: visit)
    }

    func setMark(_ mark: VisitMark, on visit: Visit) {
        visit.mark = mark
        save()
    }
}

// MARK: - Backup and restore

extension AppState {
    var allProjects: [ResearchProject] {
        (try? context.fetch(FetchDescriptor<ResearchProject>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    /// Saves projects (one, or all of them for a full backup) to a `.genboard` file.
    func exportArchive(_ projects: [ResearchProject], suggestedName: String) {
        guard !projects.isEmpty else { return }
        save()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ProjectArchive.fileExtension) ?? .zip]
        panel.nameFieldStringValue = suggestedName.replacingOccurrences(of: "/", with: "-") + "." + ProjectArchive.fileExtension
        panel.message = "Sessions, pages, screenshots, the board and theories go into one file you can keep or move to another Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProjectArchive.write(projects, to: url)
            archiveMessage = "Saved \(projects.count == 1 ? "“\(projects[0].name)”" : "\(projects.count) projects") to \(url.lastPathComponent)."
        } catch {
            archiveMessage = "Couldn't save the backup: \(error.localizedDescription)"
        }
    }

    /// Adds the projects in a `.genboard` file; existing projects are left alone.
    func importArchive() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: ProjectArchive.fileExtension) ?? .zip]
        panel.message = "Choose a Genboard backup. Its projects are added next to yours; nothing is replaced."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let projects = try ProjectArchive.read(from: url, into: context)
            archiveMessage = "Restored " + projects.map { "“\($0.name)”" }.joined(separator: ", ") + "."
        } catch {
            archiveMessage = "Couldn't restore the backup: \(error.localizedDescription)"
        }
    }
}

// MARK: - Board

extension AppState {
    static let zoomRange: ClosedRange<CGFloat> = 0.25...2.5

    @discardableResult
    func addCard(_ kind: CardKind, at point: CGPoint, in project: ResearchProject) -> BoardCard {
        let card = BoardCard(kind: kind, x: point.x, y: point.y, width: kind == .evidence ? 240 : 200, project: project)
        context.insert(card)
        addToActiveHypothesis(card)
        save()  // before reading the ID: a new model's persistentModelID changes when first saved
        selectedCardID = card.persistentModelID
        return card
    }

    /// An evidence card for a pinned page: copies the title and URL so the card outlives the visit.
    @discardableResult
    func addEvidenceCard(for visit: Visit, at point: CGPoint, in project: ResearchProject) -> BoardCard {
        let card = BoardCard(kind: .evidence, title: visit.displayTitle, x: point.x, y: point.y, width: 240, project: project)
        card.urlString = visit.urlString
        card.details = visit.note
        card.visit = visit
        card.sourceType = SourceType.guess(from: visit.urlString)
        context.insert(card)
        addToActiveHypothesis(card)
        save()  // before reading the ID: a new model's persistentModelID changes when first saved
        selectedCardID = card.persistentModelID
        return card
    }

    /// Connects two cards, unless they're already connected. Returns the new link.
    @discardableResult
    func connect(_ from: BoardCard, to: BoardCard, role: LinkRole = .related) -> BoardLink? {
        guard from !== to, let project = from.project else { return nil }
        let alreadyLinked = from.outgoing.contains { $0.to === to } || from.incoming.contains { $0.from === to }
        guard !alreadyLinked else { return nil }
        let link = BoardLink(from: from, to: to, role: role, project: project)
        context.insert(link)
        if let hypothesis = activeHypothesis(in: project) {
            link.hypotheses.append(hypothesis)
            // A connection in a theory brings both ends into it.
            for card in [from, to] where !card.hypotheses.contains(where: { $0 === hypothesis }) {
                card.hypotheses.append(hypothesis)
            }
        }
        save()
        return link
    }

    func delete(_ card: BoardCard) {
        if selectedCardID == card.persistentModelID { selectedCardID = nil }
        if let file = card.imageFile { ScreenshotStore.delete(file) }
        context.delete(card)
        save()
    }

    func delete(_ link: BoardLink) {
        if selectedLinkID == link.persistentModelID { selectedLinkID = nil }
        context.delete(link)
        save()
    }

    /// Opens a page from the board in the browser.
    func openInBrowser(_ url: URL) {
        mainMode = .browse
        if let tab = selectedTab {
            tab.load(url)
        } else {
            addTab(url)
        }
    }

    /// File types the board imports: Scapple boards and GEDCOM family trees.
    static let boardImportTypes = [UTType(filenameExtension: "scap") ?? .xml, UTType(filenameExtension: "ged") ?? .plainText]

    /// Asks for a Scapple board or GEDCOM file and adds it to the current project's board.
    func chooseBoardImport() {
        guard activeSession?.project != nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.boardImportTypes
        panel.allowsMultipleSelection = true
        panel.message = "Choose a Scapple board (.scap) or a GEDCOM family tree (.ged) to add to this project's board"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(importToBoard)
    }

    /// Adds a Scapple board or GEDCOM file to the current project's board, then shows the board.
    func importToBoard(_ url: URL) {
        guard let project = activeSession?.project else { return }
        do {
            switch url.pathExtension.lowercased() {
            case "scap": _ = try importScapple(from: url, into: project)
            case "ged": try importGedcom(from: url, into: project)
            default:
                boardImportError = "Genboard imports Scapple boards (.scap) and GEDCOM files (.ged), not “\(url.lastPathComponent)”."
                return
            }
            mainMode = .board
            boardFitRequest += 1
        } catch {
            boardImportError = "\(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Imports the people and families of a GEDCOM file as person cards, laid out as a family tree to
    /// the right of anything already on the board: parents above children, spouses side by side.
    @discardableResult
    func importGedcom(from url: URL, into project: ResearchProject) throws -> (people: Int, families: Int) {
        let result = try GedcomImporter.parse(Data(contentsOf: url))
        let rows = GedcomImporter.generations(result)
        let peopleByID = Dictionary(result.people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let originX = (project.cards.map { $0.x + $0.width }.max() ?? 0) + (project.cards.isEmpty ? 0 : 200)
        let columnWidth = 230.0, rowHeight = 170.0

        var spouses: [String: [String]] = [:]
        var parents: [String: [String]] = [:]
        for family in result.families {
            if let husband = family.husband, let wife = family.wife {
                spouses[husband, default: []].append(wife)
                spouses[wife, default: []].append(husband)
            }
            for child in family.children { parents[child, default: []] += [family.husband, family.wife].compactMap { $0 } }
        }

        var cards: [String: BoardCard] = [:]
        var columns: [String: Double] = [:]
        let maxRow = rows.values.max() ?? 0
        for row in 0...maxRow {
            // Under their parents, roughly; then each person's spouses right beside them.
            let members = result.people.map(\.id).filter { rows[$0] == row }
            let sorted = members.sorted { a, b in
                func center(_ id: String) -> Double {
                    let xs = (parents[id] ?? []).compactMap { columns[$0] }
                    return xs.isEmpty ? .infinity : xs.reduce(0, +) / Double(xs.count)
                }
                return center(a) < center(b)
            }
            var ordered: [String] = []
            for id in sorted where !ordered.contains(id) {
                ordered.append(id)
                for spouse in spouses[id] ?? [] where rows[spouse] == row && !ordered.contains(spouse) { ordered.append(spouse) }
            }
            for (column, id) in ordered.enumerated() {
                guard let person = peopleByID[id] else { continue }
                columns[id] = Double(column)
                let card = BoardCard(kind: .person, title: person.name,
                                     x: originX + Double(column) * columnWidth, y: Double(row) * rowHeight, project: project)
                card.sex = person.sex
                card.date = GedcomImporter.lifeDates(person)
                card.place = [person.birth, person.baptism].compactMap { $0?.place }.first { !$0.isEmpty } ?? ""
                card.details = GedcomImporter.details(person, sources: result.sources)
                context.insert(card)
                cards[id] = card
            }
        }

        for family in result.families {
            let couple = [family.husband, family.wife].compactMap { $0 }.compactMap { cards[$0] }
            if couple.count == 2 {
                let link = BoardLink(from: couple[0], to: couple[1], role: .spouse, project: project)
                if let marriage = family.marriage {
                    if let year = BoardChecks.firstYear(in: marriage.date) { link.label = "m. \(year)" }
                    link.note = "Married " + [marriage.date, marriage.place].filter { !$0.isEmpty }.joined(separator: ", ")
                }
                context.insert(link)
            }
            for child in family.children.compactMap({ cards[$0] }) {
                for parent in couple { context.insert(BoardLink(from: parent, to: child, role: .parent, project: project)) }
            }
        }
        save()
        return (cards.count, result.families.count)
    }

    /// Imports a Scapple board as note cards, placed to the right of anything already on the board.
    func importScapple(from url: URL, into project: ResearchProject) throws -> Int {
        let notes = try ScappleImporter.parse(Data(contentsOf: url))
        guard !notes.isEmpty else { return 0 }
        let minX = notes.map(\.x).min() ?? 0
        let minY = notes.map(\.y).min() ?? 0
        let originX = (project.cards.map { $0.x + $0.width }.max() ?? 0) + (project.cards.isEmpty ? 0 : 200)

        var cardsByID: [Int: BoardCard] = [:]
        for note in notes {
            let card = BoardCard(kind: note.imagePNG == nil ? .note : .evidence,
                                 x: originX + note.x - minX, y: note.y - minY,
                                 width: max(note.width + 20, 120), project: project)
            card.details = note.text
            card.colorHex = note.fillHex
            if let png = note.imagePNG { card.imageFile = ScreenshotStore.save(png) }
            context.insert(card)
            cardsByID[note.id] = card
        }

        // Scapple stores each connection on both notes; keep one link per pair, preferring arrows.
        var linked = Set<[Int]>()
        for note in notes {
            guard let from = cardsByID[note.id] else { continue }
            for target in note.pointsTo {
                guard let to = cardsByID[target], linked.insert([note.id, target].sorted()).inserted else { continue }
                context.insert(BoardLink(from: from, to: to, directed: true, project: project))
            }
        }
        for note in notes {
            guard let from = cardsByID[note.id] else { continue }
            for target in note.connected {
                guard let to = cardsByID[target], linked.insert([note.id, target].sorted()).inserted else { continue }
                context.insert(BoardLink(from: from, to: to, project: project))
            }
        }
        save()
        return notes.count
    }
}

// MARK: - Theories

extension AppState {
    static let theoryColors: [Color] = [.orange, .teal, .pink, .indigo, .green, .brown]

    static func theoryColor(_ hypothesis: Hypothesis) -> Color {
        theoryColors[abs(hypothesis.colorIndex) % theoryColors.count]
    }

    func activeHypothesis(in project: ResearchProject) -> Hypothesis? {
        project.hypotheses.first { $0.persistentModelID == activeHypothesisID }
    }

    @discardableResult
    func addHypothesis(to project: ResearchProject, title: String = "New theory") -> Hypothesis {
        let used = Set(project.hypotheses.map(\.colorIndex))
        let color = (0..<Self.theoryColors.count).first { !used.contains($0) } ?? project.hypotheses.count
        let hypothesis = Hypothesis(title: title, colorIndex: color, project: project)
        context.insert(hypothesis)
        // Start the theory from the selected card, if any.
        if let card = project.cards.first(where: { $0.persistentModelID == selectedCardID }) {
            card.hypotheses.append(hypothesis)
        }
        save()  // before reading the ID: a new model's persistentModelID changes when first saved
        activeHypothesisID = hypothesis.persistentModelID
        return hypothesis
    }

    func toggleActive(_ hypothesis: Hypothesis) {
        activeHypothesisID = activeHypothesisID == hypothesis.persistentModelID ? nil : hypothesis.persistentModelID
        if activeHypothesisID != nil { hypothesis.isVisible = true }
    }

    func setMembership(_ card: BoardCard, in hypothesis: Hypothesis, _ isMember: Bool) {
        if isMember {
            if !card.hypotheses.contains(where: { $0 === hypothesis }) { card.hypotheses.append(hypothesis) }
        } else {
            card.hypotheses.removeAll { $0 === hypothesis }
            // Its connections leave the theory with it.
            for link in card.outgoing + card.incoming {
                link.hypotheses.removeAll { $0 === hypothesis }
            }
        }
        save()
    }

    func addTodo(_ text: String, to hypothesis: Hypothesis) {
        let todo = TodoItem(text: text, project: hypothesis.project, fromSessionGoal: activeSession?.goal ?? "")
        todo.hypothesis = hypothesis
        context.insert(todo)
        save()
    }

    func delete(_ hypothesis: Hypothesis) {
        if activeHypothesisID == hypothesis.persistentModelID { activeHypothesisID = nil }
        context.delete(hypothesis)
        save()
    }

    private func addToActiveHypothesis(_ card: BoardCard) {
        guard let project = card.project, let hypothesis = activeHypothesis(in: project) else { return }
        card.hypotheses.append(hypothesis)
    }
}

// MARK: - AI suggestions

extension AppState {
    /// Adds the accepted suggestions under the source record: people in one row, events below,
    /// each linked to the record as supporting evidence, with roles and relationships as connections.
    func applySuggestions(_ suggestions: CardSuggestions, from source: BoardCard) {
        guard let project = source.project else { return }
        var cardsByRef: [String: BoardCard] = [:]
        var column = 0.0

        for person in suggestions.people where person.include {
            let card: BoardCard
            if let existing = person.existingCard {
                card = existing
                if card.sex == .unknown { card.sex = Sex.from(role: person.role) }
                if card.date.isEmpty { card.date = person.dates }
                if card.place.isEmpty { card.place = person.place }
            } else {
                card = addCard(.person, at: CGPoint(x: source.x + column * 230, y: source.y + 220), in: project)
                column += 1
                card.title = person.name
                card.date = person.dates
                card.place = person.place
                card.details = person.notes
                card.sex = Sex.from(role: person.role)
            }
            cardsByRef[person.id] = card
            connect(source, to: card, role: .supports)
        }

        column = 0
        for event in suggestions.events where event.include {
            let card = addCard(.event, at: CGPoint(x: source.x + column * 230, y: source.y + 400), in: project)
            column += 1
            card.title = event.title.isEmpty ? event.type.capitalized : event.title
            card.date = event.date
            card.place = event.place
            card.details = event.notes
            cardsByRef[event.id] = card
            connect(source, to: card, role: .supports)
            for participant in event.participants {
                guard let person = cardsByRef[participant.person] else { continue }
                connect(person, to: card)?.label = participant.role
            }
        }

        for relationship in suggestions.relationships where relationship.include {
            guard let from = cardsByRef[relationship.from], let to = cardsByRef[relationship.to] else { continue }
            connect(from, to: to, role: relationship.role)
        }
        selectedCardID = source.persistentModelID
        save()
    }
}
