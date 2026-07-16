import SwiftUI
import UIKit

struct AppIconOption: Identifiable {
    let id = UUID()
    let label: String
    let altName: String?   // nil = primary (the LORE ST photo)

    static let all: [AppIconOption] = [
        .init(label: "AI Slop (derogatory)", altName: nil),
        .init(label: "AI Slop (Tasteful)", altName: "AppIconClean"),
        .init(label: "Non AI Slop", altName: "AppIconDoodle"),
    ]
}

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
    @ObservedObject private var demo = DemoLocationStore.shared
    @State private var currentIcon = UIApplication.shared.alternateIconName

    private func setAppIcon(_ option: AppIconOption) {
        guard UIApplication.shared.alternateIconName != option.altName else { return }
        UIApplication.shared.setAlternateIconName(option.altName) { _ in
            currentIcon = UIApplication.shared.alternateIconName
        }
    }

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

                Section("App icon") {
                    ForEach(AppIconOption.all) { option in
                        Button {
                            setAppIcon(option)
                        } label: {
                            HStack {
                                Text(option.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if currentIcon == option.altName {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
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

                Section {
                    Picker("Location", selection: Binding(
                        get: { demo.activeName ?? "" },
                        set: { name in
                            if name.isEmpty { demo.clear() }
                            else if let p = demo.presets.first(where: { $0.name == name }) { demo.set(p) }
                        }
                    )) {
                        Text("Off (use GPS)").tag("")
                        ForEach(demo.presets) { p in
                            Text(p.name).tag(p.name)
                        }
                    }
                } header: {
                    Text("Demo location")
                } footer: {
                    Text(demo.activeName == nil
                        ? "Pretend you're standing on any street to preview its card."
                        : "Simulating \(demo.activeName!). The Street tab shows this street until you turn it off.")
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
