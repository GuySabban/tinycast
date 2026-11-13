import SwiftUI

/// The install lead card: what was typed, the cask it found, and what Homebrew already knows.
struct PackageInstallCard: View {
    @Environment(\.metrics) private var metrics
    let candidate: PackageCandidate
    let selected: Bool

    var body: some View {
        HStack(spacing: 0) {
            switch candidate.state {
            case .match(let entry, _):
                LeadCardColumn(text: AttributedString(candidate.requestedName), badge: String(localized: "Install"))
                Image(systemName: "arrow.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tertiary)
                LeadCardColumn(text: AttributedString(entry.token), badge: status(of: entry))
            case .loadingIndex:
                LeadCardColumn(
                    text: AttributedString(String(localized: "Loading Homebrew's list…")), badge: nil, weight: .regular)
            case .indexUnavailable:
                LeadCardColumn(
                    text: AttributedString(String(localized: "Homebrew's list is unavailable")),
                    badge: String(localized: "Check your connection"), weight: .regular)
            case .noMatch:
                LeadCardColumn(
                    text: AttributedString(String(localized: "No cask matches “\(candidate.requestedName)”")),
                    badge: String(localized: "Homebrew"), weight: .regular)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.xxxl)
        .leadCard(selected: selected)
    }

    private func status(of entry: CaskIndex.Entry) -> String {
        switch candidate.installation {
        case .installed: String(localized: "Installed with Homebrew")
        case .appMissing(let app): String(localized: "\(app) is missing · Reinstall")
        case nil:
            String(localized: "\(entry.installs.formatted()) installs this month")
        }
    }
}
