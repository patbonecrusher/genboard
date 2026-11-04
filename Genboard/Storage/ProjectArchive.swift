import Foundation
import SwiftData

/// Backup and restore: one or more projects, with their sessions, pages, screenshots, board and
/// theories, in a single `.genboard` file (a zip holding `project.json` and the screenshots).
/// Restoring always adds new projects; it never replaces what's already there.
enum ProjectArchive {
    static let fileExtension = "genboard"
    static let currentVersion = 1

    // MARK: File format

    nonisolated struct Archive: Codable {
        var version: Int
        var exportedAt: Date
        var projects: [Project]
    }

    nonisolated struct Project: Codable {
        var name: String
        var createdAt: Date
        var sessions: [Session]
        var todos: [Todo]
        var cards: [Card]
        var links: [Link]
        var theories: [Theory]
    }

    nonisolated struct Session: Codable {
        var goal: String
        var startedAt: Date
        var endedAt: Date?
        var summary: String
        var openQuestions: String
        var summarySkipped: Bool
        var savedTabURLs: [String]
        var aiInputTokens: Int
        var aiOutputTokens: Int
        var aiCostUSD: Double
        var visits: [Visit]
    }

    nonisolated struct Visit: Codable {
        /// Archive-local ID that cards refer to.
        var id: Int
        var urlString: String
        var title: String
        var visitedAt: Date
        var mark: String
        var note: String
        var selectedText: String
        var screenshotFile: String?
        var transcription: String
    }

    nonisolated struct Todo: Codable {
        var text: String
        var done: Bool
        var createdAt: Date
        var fromSessionGoal: String
        var theory: Int?
    }

    nonisolated struct Card: Codable {
        var id: Int
        var kind: String
        var title: String
        var details: String
        var date: String
        var place: String
        var flag: String
        var sex: String
        var x: Double
        var y: Double
        var width: Double
        var colorHex: String?
        var imageFile: String?
        var urlString: String
        var citation: String
        var repository: String
        var sourceType: String
        var information: String
        var createdAt: Date
        var visit: Int?
        var theories: [Int]
    }

    nonisolated struct Link: Codable {
        var role: String
        var label: String
        var note: String
        var directed: Bool
        var from: Int
        var to: Int
        var theories: [Int]
    }

    nonisolated struct Theory: Codable {
        var id: Int
        var title: String
        var statement: String
        var status: String
        var colorIndex: Int
        var isVisible: Bool
        var createdAt: Date
    }

    enum ArchiveError: LocalizedError {
        case notAnArchive
        case newerVersion(Int)
        case zipFailed

        var errorDescription: String? {
            switch self {
            case .notAnArchive: "This isn't a Genboard backup."
            case .newerVersion(let version): "This backup was made by a newer version of Genboard (format \(version)). Update Genboard to open it."
            case .zipFailed: "The backup file couldn't be written or read."
            }
        }
    }

    // MARK: Snapshot and restore

    static func snapshot(_ projects: [ResearchProject], now: Date = .now) -> Archive {
        Archive(version: currentVersion, exportedAt: now, projects: projects.map(snapshot))
    }

    private static func snapshot(_ project: ResearchProject) -> Project {
        let theories = project.hypotheses.sorted { $0.createdAt < $1.createdAt }
        let theoryIDs = Dictionary(uniqueKeysWithValues: theories.enumerated().map { (ObjectIdentifier($1), $0) })
        func ids(_ list: [Hypothesis]) -> [Int] { list.compactMap { theoryIDs[ObjectIdentifier($0)] } }

        var visitIDs: [ObjectIdentifier: Int] = [:]
        let sessions = project.sessions.sorted { $0.startedAt < $1.startedAt }.map { session in
            Session(goal: session.goal, startedAt: session.startedAt, endedAt: session.endedAt, summary: session.summary,
                    openQuestions: session.openQuestions, summarySkipped: session.summarySkipped,
                    savedTabURLs: session.savedTabURLs, aiInputTokens: session.aiInputTokens,
                    aiOutputTokens: session.aiOutputTokens, aiCostUSD: session.aiCostUSD,
                    visits: session.sortedVisits.map { visit in
                        let id = visitIDs.count
                        visitIDs[ObjectIdentifier(visit)] = id
                        return Visit(id: id, urlString: visit.urlString, title: visit.title, visitedAt: visit.visitedAt,
                                     mark: visit.markRaw, note: visit.note, selectedText: visit.selectedText,
                                     screenshotFile: visit.screenshotFile, transcription: visit.transcription)
                    })
        }

        let cards = project.cards.sorted { $0.createdAt < $1.createdAt }
        let cardIDs = Dictionary(uniqueKeysWithValues: cards.enumerated().map { (ObjectIdentifier($1), $0) })
        return Project(
            name: project.name,
            createdAt: project.createdAt,
            sessions: sessions,
            todos: project.todos.sorted { $0.createdAt < $1.createdAt }.map { todo in
                Todo(text: todo.text, done: todo.done, createdAt: todo.createdAt, fromSessionGoal: todo.fromSessionGoal,
                     theory: todo.hypothesis.flatMap { theoryIDs[ObjectIdentifier($0)] })
            },
            cards: cards.enumerated().map { index, card in
                Card(id: index, kind: card.kindRaw, title: card.title, details: card.details, date: card.date,
                     place: card.place, flag: card.flagRaw, sex: card.sexRaw, x: card.x, y: card.y, width: card.width,
                     colorHex: card.colorHex, imageFile: card.imageFile, urlString: card.urlString,
                     citation: card.citation, repository: card.repository, sourceType: card.sourceTypeRaw,
                     information: card.informationRaw, createdAt: card.createdAt,
                     visit: card.visit.flatMap { visitIDs[ObjectIdentifier($0)] }, theories: ids(card.hypotheses))
            },
            links: project.links.compactMap { link in
                guard let from = link.from.flatMap({ cardIDs[ObjectIdentifier($0)] }),
                      let to = link.to.flatMap({ cardIDs[ObjectIdentifier($0)] }) else { return nil }
                return Link(role: link.roleRaw, label: link.label, note: link.note, directed: link.directed,
                            from: from, to: to, theories: ids(link.hypotheses))
            },
            theories: theories.enumerated().map { index, theory in
                Theory(id: index, title: theory.title, statement: theory.statement, status: theory.statusRaw,
                       colorIndex: theory.colorIndex, isVisible: theory.isVisible, createdAt: theory.createdAt)
            })
    }

    /// Adds the archive's projects to the store. `renameFile` maps a screenshot file name in the
    /// archive to its new name in the screenshot folder (nil when the image wasn't restored).
    @discardableResult
    static func restore(_ archive: Archive, into context: ModelContext,
                        renameFile: (String) -> String? = { $0 }) throws -> [ResearchProject] {
        guard archive.version <= currentVersion else { throw ArchiveError.newerVersion(archive.version) }
        let existingNames = Set(try context.fetch(FetchDescriptor<ResearchProject>()).map(\.name))
        return archive.projects.map { saved in
            let name = existingNames.contains(saved.name) ? "\(saved.name) (restored)" : saved.name
            let project = ResearchProject(name: name)
            project.createdAt = saved.createdAt
            context.insert(project)

            var theories: [Int: Hypothesis] = [:]
            for saved in saved.theories {
                let theory = Hypothesis(title: saved.title, colorIndex: saved.colorIndex, project: project)
                theory.statement = saved.statement
                theory.statusRaw = saved.status
                theory.isVisible = saved.isVisible
                theory.createdAt = saved.createdAt
                context.insert(theory)
                theories[saved.id] = theory
            }

            var visits: [Int: Genboard.Visit] = [:]
            for saved in saved.sessions {
                let session = ResearchSession(goal: saved.goal, project: project)
                session.startedAt = saved.startedAt
                // Restored sessions are closed; the researcher reopens one to continue.
                session.endedAt = saved.endedAt ?? saved.startedAt
                session.summary = saved.summary
                session.openQuestions = saved.openQuestions
                session.summarySkipped = saved.summarySkipped
                session.savedTabURLs = saved.savedTabURLs
                session.aiInputTokens = saved.aiInputTokens
                session.aiOutputTokens = saved.aiOutputTokens
                session.aiCostUSD = saved.aiCostUSD
                context.insert(session)
                for savedVisit in saved.visits {
                    let visit = Genboard.Visit(url: URL(string: savedVisit.urlString) ?? URL(string: "about:blank")!,
                                               title: savedVisit.title, session: session)
                    visit.urlString = savedVisit.urlString
                    visit.visitedAt = savedVisit.visitedAt
                    visit.markRaw = savedVisit.mark
                    visit.note = savedVisit.note
                    visit.selectedText = savedVisit.selectedText
                    visit.screenshotFile = savedVisit.screenshotFile.flatMap(renameFile)
                    visit.transcription = savedVisit.transcription
                    context.insert(visit)
                    visits[savedVisit.id] = visit
                }
            }

            for saved in saved.todos {
                let todo = TodoItem(text: saved.text, project: project, fromSessionGoal: saved.fromSessionGoal)
                todo.done = saved.done
                todo.createdAt = saved.createdAt
                todo.hypothesis = saved.theory.flatMap { theories[$0] }
                context.insert(todo)
            }

            var cards: [Int: BoardCard] = [:]
            for saved in saved.cards {
                let card = BoardCard(kind: CardKind(rawValue: saved.kind) ?? .note, title: saved.title,
                                     x: saved.x, y: saved.y, width: saved.width, project: project)
                card.kindRaw = saved.kind
                card.details = saved.details
                card.date = saved.date
                card.place = saved.place
                card.flagRaw = saved.flag
                card.sexRaw = saved.sex
                card.colorHex = saved.colorHex
                card.imageFile = saved.imageFile.flatMap(renameFile)
                card.urlString = saved.urlString
                card.citation = saved.citation
                card.repository = saved.repository
                card.sourceTypeRaw = saved.sourceType
                card.informationRaw = saved.information
                card.createdAt = saved.createdAt
                card.visit = saved.visit.flatMap { visits[$0] }
                context.insert(card)
                card.hypotheses = saved.theories.compactMap { theories[$0] }
                cards[saved.id] = card
            }

            for saved in saved.links {
                guard let from = cards[saved.from], let to = cards[saved.to] else { continue }
                let link = BoardLink(from: from, to: to, role: LinkRole(rawValue: saved.role) ?? .related,
                                     directed: saved.directed, project: project)
                link.roleRaw = saved.role
                link.label = saved.label
                link.note = saved.note
                context.insert(link)
                link.hypotheses = saved.theories.compactMap { theories[$0] }
            }
            return project
        }
    }

    // MARK: Files

    static func encode(_ archive: Archive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> Archive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // The version first, so a newer format gets a clear message rather than a decode error.
        struct Header: Decodable { var version: Int }
        guard let header = try? decoder.decode(Header.self, from: data) else { throw ArchiveError.notAnArchive }
        guard header.version <= currentVersion else { throw ArchiveError.newerVersion(header.version) }
        guard let archive = try? decoder.decode(Archive.self, from: data) else { throw ArchiveError.notAnArchive }
        return archive
    }

    /// Writes the projects and their screenshots to a `.genboard` file.
    static func write(_ projects: [ResearchProject], to url: URL, screenshots: URL = ScreenshotStore.directory) throws {
        let archive = snapshot(projects)
        let folder = FileManager.default.temporaryDirectory.appending(path: "genboard-export-\(UUID())", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let images = folder.appending(path: "Screenshots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try encode(archive).write(to: folder.appending(path: "project.json"))
        let files = archive.projects.flatMap { project in
            project.sessions.flatMap { $0.visits.compactMap(\.screenshotFile) } + project.cards.compactMap(\.imageFile)
        }
        for file in Set(files) {
            let source = screenshots.appending(path: file)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: images.appending(path: file))
            }
        }
        try? FileManager.default.removeItem(at: url)
        try ditto(["-c", "-k", folder.path, url.path])
    }

    /// Restores every project in a `.genboard` file, copying its screenshots in under new names.
    @discardableResult
    static func read(from url: URL, into context: ModelContext,
                     screenshots: URL = ScreenshotStore.directory) throws -> [ResearchProject] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "genboard-import-\(UUID())", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try ditto(["-x", "-k", url.path, folder.path])
        guard let data = try? Data(contentsOf: folder.appending(path: "project.json")) else { throw ArchiveError.notAnArchive }
        let archive = try decode(data)
        let images = folder.appending(path: "Screenshots")
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
        var renamed: [String: String] = [:]
        let projects = try restore(archive, into: context) { file in
            if let done = renamed[file] { return done }
            let source = images.appending(path: file)
            guard !file.contains("/"), FileManager.default.fileExists(atPath: source.path) else { return nil }
            let name = UUID().uuidString + "." + (source.pathExtension.isEmpty ? "png" : source.pathExtension)
            guard (try? FileManager.default.copyItem(at: source, to: screenshots.appending(path: name))) != nil else { return nil }
            renamed[file] = name
            return name
        }
        try context.save()
        return projects
    }

    private static func ditto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ArchiveError.zipFailed }
    }
}
