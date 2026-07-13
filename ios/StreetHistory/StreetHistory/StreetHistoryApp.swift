import SwiftUI
import UserNotifications

final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

enum AppTab: String, CaseIterable {
    case street, map, journeys, favorites, settings

    var label: String {
        switch self {
        case .street: return "Street"
        case .map: return "Map"
        case .journeys: return "Journeys"
        case .favorites: return "Favorites"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .street: return "signpost.right.and.left.fill"
        case .map: return "map"
        case .journeys: return "figure.walk"
        case .favorites: return "heart"
        case .settings: return "gearshape"
        }
    }
}

@main
struct StreetHistoryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var journeyStore = JourneyStore()
    @State private var showLaunch = true
    @State private var selectedTab: AppTab = .street
    @AppStorage("appTheme") private var appTheme = AppTheme.system.rawValue
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    private let accent = Color(red: 0.40, green: 0.24, blue: 0.14)

    var body: some Scene {
        WindowGroup {
            ZStack {
                VStack(spacing: 0) {
                    ZStack {
                        switch selectedTab {
                        case .street:
                            ContentView(journeyStore: journeyStore)
                        case .map:
                            FactMapView()
                        case .journeys:
                            JourneysView(journeyStore: journeyStore)
                        case .favorites:
                            FavoritesView(journeyStore: journeyStore)
                        case .settings:
                            SettingsView(journeyStore: journeyStore)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    tabBar
                }
                .tint(accent)
                .preferredColorScheme(AppTheme(rawValue: appTheme)?.colorScheme)

                if showLaunch {
                    LaunchScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showLaunch = false
                    }
                }
            }
            .fullScreenCover(isPresented: .init(
                get: { !hasSeenOnboarding && !showLaunch },
                set: { presented in if !presented { hasSeenOnboarding = true } }
            )) {
                OnboardingView(
                    isPresented: .init(
                        get: { !hasSeenOnboarding },
                        set: { presented in if !presented { hasSeenOnboarding = true } }
                    ),
                    journeyStore: journeyStore
                )
            }
        }
    }

    private var tabBar: some View {
        HStack {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab == .favorites && selectedTab == .favorites ? "heart.fill" : tab.icon)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tab.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(selectedTab == tab ? accent : Color.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    let notificationDelegate = AppNotificationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        return true
    }
}
