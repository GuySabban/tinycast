import Foundation

/// ⌘K on the install card: the card's own cask first, then the other matches by installs.
@MainActor
enum PackageActionsMenu {
    static func content(
        candidate: PackageCandidate, coordinator: PackageInstallCoordinator
    ) -> PopoverMenuContent? {
        guard case .match(let entry, let alternates) = candidate.state else { return nil }
        var items = [
            PopoverMenuItem(
                title: primaryTitle(for: candidate), icon: .symbol("shippingbox"), shortcut: "↵"
            ) { coordinator.install(token: entry.token) },
            PopoverMenuItem(title: String(localized: "Copy Install Command"), icon: .symbol("doc.on.doc")) {
                coordinator.copyInstallCommand(token: entry.token)
            },
            PopoverMenuItem(title: String(localized: "Open Homebrew Page"), icon: .symbol("safari")) {
                coordinator.openHomebrewPage(token: entry.token)
            },
        ]
        items += alternates.enumerated().map { offset, alternate in
            PopoverMenuItem(
                title: alternate.token, icon: .symbol("shippingbox"),
                sectionTitle: offset == 0 ? String(localized: "Other Matches") : nil,
                startsSection: offset == 0,
                detail: String(localized: "\(alternate.installs) installs")
            ) { coordinator.install(token: alternate.token) }
        }
        return PopoverMenuContent(header: entry.token, items: items)
    }

    /// Also the action pill's title, so the pill and the menu never name Return differently.
    static func primaryTitle(for candidate: PackageCandidate) -> String {
        switch candidate.installation {
        case .appMissing: String(localized: "Reinstall with Homebrew")
        case .installed: String(localized: "Open Application")
        case nil: String(localized: "Install with Homebrew")
        }
    }
}
