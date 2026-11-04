import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Picks what the report covers and its format, then saves it.
struct ReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: ResearchProject
    @State private var theoryID: PersistentIdentifier?
    @State private var format = Format.pdf
    @State private var error: String?

    enum Format: String, CaseIterable, Identifiable {
        case pdf = "PDF", markdown = "Markdown", html = "Web Page"
        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .pdf: "pdf"
            case .markdown: "md"
            case .html: "html"
            }
        }
    }

    private var theories: [Hypothesis] { project.hypotheses.sorted { $0.createdAt < $1.createdAt } }

    private var report: ResearchReport {
        if let theory = theories.first(where: { $0.persistentModelID == theoryID }) {
            return ResearchReport(project: project, scope: .theory(theory))
        }
        return ResearchReport(project: project)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Research Report").font(.title2.bold())
            Text("A write-up to share with family or a genealogical society: theories with their evidence for and against, people, sources with citations, and the research log.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                Picker("Covers", selection: $theoryID) {
                    Text("The whole project").tag(PersistentIdentifier?.none)
                    if !theories.isEmpty {
                        Divider()
                        ForEach(theories) { Text("Theory: \($0.title)").tag(Optional($0.persistentModelID)) }
                    }
                }
                Picker("Format", selection: $format) {
                    ForEach(Format.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .formStyle(.columns)
            GroupBox {
                ScrollView {
                    Text(report.markdown)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 220)
            } label: {
                Text("Preview").font(.caption)
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save…", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func save() {
        let report = report
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .data]
        panel.nameFieldStringValue = report.title.replacingOccurrences(of: "/", with: "-") + "." + format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch format {
            case .pdf: try report.pdfData().write(to: url)
            case .markdown: try report.markdown.write(to: url, atomically: true, encoding: .utf8)
            case .html: try report.html.write(to: url, atomically: true, encoding: .utf8)
            }
            dismiss()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            self.error = "Couldn't save the report: \(error.localizedDescription)"
        }
    }
}
