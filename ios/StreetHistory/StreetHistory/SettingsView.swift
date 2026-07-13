import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true
    @ObservedObject var journeyStore: JourneyStore

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var bugReportURL: URL? {
        let subject = "StreetLore bug report v\(appVersion)"
        let body = """


        ---
        Version: \(appVersion)
        iOS: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "ruoccoj19@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.label).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Notifications") {
                    if journeyStore.notificationsAuthorized {
                        Label("New street alerts on", systemImage: "bell.badge.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            Task { await journeyStore.requestNotificationPermissionIfNeeded() }
                        } label: {
                            Label("Enable new street alerts", systemImage: "bell.badge")
                        }
                    }
                }

                Section("Help") {
                    if let url = bugReportURL {
                        Link(destination: url) {
                            Label("Report a bug", systemImage: "ladybug")
                        }
                    }
                    Button {
                        hasSeenOnboarding = false
                    } label: {
                        Label("Replay walkthrough", systemImage: "play.circle")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Streets explored", value: "\(journeyStore.streetsExploredCount)")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
