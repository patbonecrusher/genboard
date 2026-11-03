import SwiftUI

struct AssistantView: View {
    @Environment(AppState.self) private var app
    @Environment(AISettings.self) private var aiSettings
    let session: ResearchSession
    @State private var input = ""
    @AppStorage("assistant.attachPageText") private var attachPageText = true
    @AppStorage("assistant.attachScreenshot") private var attachScreenshot = false

    var body: some View {
        let chat = app.chat
        VStack(spacing: 0) {
            if !aiSettings.hasAPIKey {
                HStack {
                    Text("Add your Anthropic API key to use the assistant.")
                    Spacer()
                    SettingsLink { Text("Settings…") }
                }
                .font(.callout)
                .padding(10)
                .background(Color.orange.opacity(0.1))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.lines.isEmpty {
                            Text("Ask about this research. The assistant sees your pins, notes, dead ends, to-dos and earlier session summaries, plus the current page if you attach it.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(chat.lines) { line in
                            ChatBubble(line: line).id(line.id)
                        }
                        if chat.isSending {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Thinking…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let error = chat.error {
                            Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: chat.lines.count) {
                    if let last = chat.lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Toggle("Page text", isOn: $attachPageText)
                    Toggle("Screenshot", isOn: $attachScreenshot)
                }
                .toggleStyle(.checkbox)
                .font(.caption)
                HStack(alignment: .bottom) {
                    TextField("Ask about this research…", text: $input, axis: .vertical)
                        .lineLimit(1...6)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(send)
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .buttonStyle(.borderless)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isSending || !aiSettings.hasAPIKey)
                }
                Text("Session AI cost: \(session.aiCostUSD.formatted(.currency(code: "USD").precision(.fractionLength(2)))) · \(session.aiInputTokens.formatted()) in / \(session.aiOutputTokens.formatted()) out tokens")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
    }

    private func send() {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !app.chat.isSending, aiSettings.hasAPIKey else { return }
        input = ""
        Task { await app.askAssistant(question, attachPageText: attachPageText, attachScreenshot: attachScreenshot) }
    }
}

private struct ChatBubble: View {
    let line: ChatLine

    var body: some View {
        VStack(alignment: line.role == .user ? .trailing : .leading, spacing: 2) {
            Text(markdown)
                .textSelection(.enabled)
                .padding(8)
                .background(line.role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8))
            if !line.detail.isEmpty {
                Text(line.detail).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: line.role == .user ? .trailing : .leading)
    }

    private var markdown: AttributedString {
        (try? AttributedString(markdown: line.text,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(line.text)
    }
}

struct SettingsView: View {
    @Environment(AISettings.self) private var settings
    @State private var apiKey = ""
    @State private var saved = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Anthropic API") {
                SecureField("API key", text: $apiKey, prompt: Text(settings.hasAPIKey ? "Saved; paste to replace" : "sk-ant-…"))
                HStack {
                    Button("Save Key") {
                        settings.setAPIKey(apiKey)
                        apiKey = ""
                        saved = true
                    }
                    .disabled(apiKey.isEmpty)
                    if settings.hasAPIKey {
                        Button("Remove Key", role: .destructive) { settings.setAPIKey("") }
                    }
                    if saved { Text("Saved").foregroundStyle(.secondary) }
                }
                Text("Stored in your macOS Keychain. Create a key at console.anthropic.com; usage is billed to that account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Models") {
                modelPicker("Questions", selection: $settings.chatModel)
                modelPicker("Transcribing records", selection: $settings.transcriptionModel)
                modelPicker("Session summaries", selection: $settings.summaryModel)
                Picker("Effort", selection: $settings.effort) {
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }
                Text("Higher effort thinks longer: better on hard records and conflicts, but slower and costlier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .padding()
    }

    private func modelPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ModelCatalog.all) { model in
                Text("\(model.name) · $\(model.inputPrice.formatted()) / $\(model.outputPrice.formatted()) per M tokens")
                    .tag(model.id)
            }
        }
    }
}
