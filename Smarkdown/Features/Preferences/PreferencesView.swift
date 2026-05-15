import SwiftUI

struct PreferencesView: View {

    @AppStorage(LLMProvider.Keys.provider)     private var providerRaw  = LLMProvider.anthropic.rawValue
    @AppStorage(LLMProvider.Keys.anthropicKey) private var anthropicKey = ""
    @AppStorage(LLMProvider.Keys.localBaseURL) private var localBaseURL = LLMProvider.Defaults.localBaseURL
    @AppStorage(LLMProvider.Keys.localModel)   private var localModel   = LLMProvider.Defaults.localModel
    @AppStorage(LLMProvider.Keys.braveAPIKey)  private var braveAPIKey  = ""

    private var provider: LLMProvider {
        LLMProvider(rawValue: providerRaw) ?? .anthropic
    }

    var body: some View {
        Form {
            // ── Provider picker ───────────────────────────────────
            Section("AI Classification") {
                Picker("Provider", selection: $providerRaw) {
                    Text("Anthropic (Cloud)").tag(LLMProvider.anthropic.rawValue)
                    Text("Local (Ollama / LM Studio)").tag(LLMProvider.local.rawValue)
                }
                .pickerStyle(.radioGroup)

                Text("Automatic classification runs 8 seconds after you stop typing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Anthropic section ─────────────────────────────────
            if provider == .anthropic {
                AnthropicSection(apiKey: $anthropicKey)
            }

            // ── Local section ─────────────────────────────────────
            if provider == .local {
                LocalSection(baseURL: $localBaseURL, model: $localModel)
            }

            // ── Web search ────────────────────────────────────────
            WebSearchSection(apiKey: $braveAPIKey)
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }
}

// MARK: - Anthropic section

private struct AnthropicSection: View {
    @Binding var apiKey: String
    @State private var isRevealed = false

    var body: some View {
        Section {
            LabeledContent("API key") {
                HStack(spacing: 6) {
                    Group {
                        if isRevealed {
                            TextField("sk-ant-…", text: $apiKey)
                        } else {
                            SecureField("sk-ant-…", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)
                    .help(isRevealed ? "Hide key" : "Show key")
                }
            }

            Text("The key is stored locally on this device only. Get yours at **console.anthropic.com**.")
                .font(.caption)
                .foregroundStyle(.secondary)

        } header: {
            Text("Anthropic")
        } footer: {
            keyStatusLabel
        }
    }

    @ViewBuilder
    private var keyStatusLabel: some View {
        let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            Label("No key — automatic classification disabled.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if trimmed.hasPrefix("sk-ant-") {
            Label("Key saved.", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Label("Unexpected format (expected sk-ant-…).", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - Web Search section

private struct WebSearchSection: View {
    @Binding var apiKey: String
    @State private var isRevealed = false

    var body: some View {
        Section {
            LabeledContent("Brave API key") {
                HStack(spacing: 6) {
                    Group {
                        if isRevealed {
                            TextField("BSA…", text: $apiKey)
                        } else {
                            SecureField("BSA…", text: $apiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    Button {
                        isRevealed.toggle()
                    } label: {
                        Image(systemName: isRevealed ? "eye.slash" : "eye")
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)
                    .help(isRevealed ? "Hide key" : "Show key")
                }
            }

            Text("Used for Idea and Question Briefs. Free tier: 2,000 queries/month. Get yours at **api.search.brave.com**.")
                .font(.caption)
                .foregroundStyle(.secondary)

        } header: {
            Text("Web Search")
        } footer: {
            let trimmed = apiKey.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                Label("No key — briefs will use document context only.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Key saved.", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }
}

// MARK: - Local section

private struct LocalSection: View {
    @Binding var baseURL: String
    @Binding var model: String

    enum ReachabilityStatus { case idle, checking, reachable, unreachable }
    @State private var status: ReachabilityStatus = .idle

    var body: some View {
        Section {
            LabeledContent("Base URL") {
                TextField(LLMProvider.Defaults.localBaseURL, text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: baseURL) { _, _ in status = .idle }
            }

            LabeledContent("Model") {
                TextField(LLMProvider.Defaults.localModel, text: $model)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Button("Check connection") {
                    Task { await checkReachability() }
                }

                statusBadge
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Requires a running Ollama or LM Studio server.")
                Text("Popular models: **llama3.1:8b**, **mistral:7b**, **phi3:mini**")
                Text("Ollama install: **brew install ollama** → **ollama serve**")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        } header: {
            Text("Local Server")
        }
        .onAppear {
            Task { await checkReachability() }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Checking…").font(.caption).foregroundStyle(.secondary)
            }
        case .reachable:
            Label("Server reachable", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case .unreachable:
            Label("Not reachable", systemImage: "xmark.circle.fill")
                .font(.caption).foregroundStyle(.red)
        }
    }

    private func checkReachability() async {
        let raw = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // /v1/models is the OpenAI-standard models endpoint — supported by both
        // Ollama and LM Studio. /api/tags is Ollama-only and returns 404 on LM Studio.
        guard !raw.isEmpty, let url = URL(string: "\(raw)/v1/models") else {
            status = .unreachable
            return
        }
        status = .checking
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            status = (response as? HTTPURLResponse)?.statusCode == 200 ? .reachable : .unreachable
        } catch {
            status = .unreachable
        }
    }
}
