import Foundation

/// The ⌘K menu for one web row; a placeholder has nothing to act on.
@MainActor
enum WebSearchActionsMenu {
    static func content(
        row: WebSearchRow, query: String, coordinator: WebSearchCoordinator
    ) -> PopoverMenuContent? {
        switch row {
        case .placeholder:
            return nil
        case .noResults:
            return PopoverMenuContent(header: nil, items: [searchAgain(query, coordinator: coordinator)])
        case .result(let result):
            return PopoverMenuContent(
                header: result.host,
                items: [
                    PopoverMenuItem(
                        title: String(localized: "Open in Browser"), icon: .symbol("safari"), shortcut: "↵"
                    ) { coordinator.open(row) },
                    PopoverMenuItem(title: String(localized: "Copy Link"), icon: .symbol("link")) {
                        coordinator.copyLink(result)
                    },
                    searchAgain(query, coordinator: coordinator),
                ])
        case .failure(let failure):
            let primary =
                WebSearchCoordinator.needsSettings(failure)
                ? PopoverMenuItem(
                    title: String(localized: "Open Web Search Settings"), icon: .symbol("gearshape"),
                    shortcut: "↵"
                ) { coordinator.open(row) }
                : PopoverMenuItem(
                    title: String(localized: "Try Again"), icon: .symbol("arrow.clockwise"), shortcut: "↵"
                ) { coordinator.open(row) }
            return PopoverMenuContent(header: nil, items: [primary])
        }
    }

    /// The pill's title; a placeholder has no action, so its title is never shown.
    static func primaryTitle(for row: WebSearchRow) -> String {
        switch row {
        case .placeholder: return String(localized: "Searching the web")
        case .noResults: return String(localized: "Search Again")
        case .result: return String(localized: "Open in Browser")
        case .failure(let failure):
            return WebSearchCoordinator.needsSettings(failure)
                ? String(localized: "Open Web Search Settings") : String(localized: "Try Again")
        }
    }

    private static func searchAgain(_ query: String, coordinator: WebSearchCoordinator) -> PopoverMenuItem {
        var item = PopoverMenuItem(title: String(localized: "Search Again"), icon: .symbol("arrow.clockwise")) {
            coordinator.searchAgain(query)
        }
        item.startsSection = true
        return item
    }
}
