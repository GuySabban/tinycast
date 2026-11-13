import SwiftUI

/// One section in the Applications pane; the coordinator applies the switch, not the view.
struct PackageInstallSettingsSection: View {
    @Environment(AppCore.self) private var core

    var body: some View {
        let coordinator = core.packageInstallCoordinator
        Section {
            Toggle(
                isOn: Binding(
                    get: { coordinator.settings.isEnabled }, set: { coordinator.setEnabled($0) })
            ) {
                Text("Install apps with Homebrew")
                Text(Self.subtitle)
            }
        } header: {
            Text("Homebrew")
        }
    }

    private static var subtitle: String {
        [
            String(localized: "Type “install” and an app's name to install it."),
            String(localized: "Homebrew's list of apps is downloaded once a day."),
            String(localized: "An app's name goes to Homebrew only when you press Return."),
        ].joined(separator: " ")
    }
}
