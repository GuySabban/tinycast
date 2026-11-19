import SwiftUI

/// One web row: a result as plain text, a static placeholder, or the single failure line.
struct WebSearchRowView: View {

    @Environment(\.metrics) private var metrics
    let row: WebSearchRow
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            icon
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            content
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var icon: some View {
        let name = if case .failure = row { "exclamationmark.triangle" } else { "globe" }
        SymbolImage(name: name, size: metrics.size.resultRowIcon - metrics.spacing.xs * 2, monochrome: true)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var content: some View {
        switch row {
        case .placeholder:
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(verbatim: String(repeating: "W", count: 28)).font(metrics.typography.rowTitle)
                Text(verbatim: String(repeating: "W", count: 44)).font(metrics.typography.rowTrailing)
            }
            .lineLimit(1)
            .redacted(reason: .placeholder)
            .accessibilityLabel(Text("Searching the web"))
        case .result(let result):
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(verbatim: result.title)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !result.snippet.isEmpty {
                    Text(verbatim: result.snippet)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)
        case .noResults:
            Text("No web results")
                .font(metrics.typography.rowTitle)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
        case .failure(let failure):
            Text(Self.message(for: failure))
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
    }

    @ViewBuilder private var trailing: some View {
        if case .result(let result) = row {
            Text(verbatim: Self.detail(for: result))
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    static func detail(for result: WebSearchResult) -> String {
        guard let published = result.published else { return result.host }
        let age = published.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return "\(result.host) · \(age)"
    }

    static func message(for failure: WebSearchFailure) -> String {
        switch failure {
        case .missingKey: String(localized: "Add an Exa API key in Settings to search the web")
        case .unauthorized: String(localized: "Exa didn’t accept the API key. Check it in Settings")
        case .outOfCredit: String(localized: "Your Exa account is out of credit")
        case .rateLimited: String(localized: "Too many web searches. Try again in a moment")
        case .offline: String(localized: "Couldn’t reach Exa. Check your connection")
        case .keyUnreadable: String(localized: "The keychain didn’t release the Exa API key. Try again")
        case .server, .malformedReply, .cancelled: String(localized: "Web search failed. Try again")
        }
    }
}
