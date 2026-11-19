import SwiftUI

/// One section in the Fallbacks pane. The key is written and removed, never read back into a field.
struct WebSearchSettingsSection: View {
    @Environment(AppCore.self) private var core
    @State private var draft = ""
    @State private var failure: String?

    private static let keysPage = URL(string: "https://dashboard.exa.ai/api-keys")!

    var body: some View {
        let settings = core.webSearchSettings
        Section {
            Toggle(isOn: Binding(get: { settings.isEnabled }, set: { core.webSearchCoordinator.setEnabled($0) })) {
                Text("Show web results")
                Text(Self.subtitle)
            }
            switch settings.keyStatus {
            case .stored:
                LabeledContent("Exa API key") {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("Stored in your keychain")
                            .foregroundStyle(.secondary)
                        Button("Remove", role: .destructive) { save(nil) }
                    }
                }
            case .missing:
                RevealableSecureField(
                    title: String(localized: "Exa API key"), text: $draft,
                    prompt: Text("Paste your key"))
                    .onSubmit { save(draft) }
                HStack {
                    Link("Get a free key from Exa", destination: Self.keysPage)
                    Spacer()
                    Button("Save Key") { save(draft) }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            case .unreadable:
                LabeledContent("Exa API key") {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(Self.unreadableNote)
                            .foregroundStyle(.secondary)
                        Button("Check Again") { settings.refreshKeyStatus() }
                    }
                }
            }
            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.destructive)
            }
        } header: {
            Text("Web Search")
        }
    }

    private func save(_ key: String?) {
        do {
            try core.webSearchSettings.setKey(key)
            draft = ""
            failure = nil
        } catch {
            failure = [
                String(localized: "The keychain refused the change."),
                String(localized: "Try again."),
            ].joined(separator: " ")
        }
    }

    private static var unreadableNote: String {
        [
            String(localized: "The keychain did not answer."),
            String(localized: "Your key may still be stored."),
        ].joined(separator: " ")
    }

    private static var subtitle: String {
        [
            String(localized: "Press Return on Search the Web to list results from Exa here."),
            String(localized: "Only the query is sent, only when you request a web search, and Exa may keep it."),
            String(localized: "Results stay in memory and are never saved."),
        ].joined(separator: " ")
    }
}
