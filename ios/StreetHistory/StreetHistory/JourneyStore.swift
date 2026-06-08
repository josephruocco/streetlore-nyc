import Foundation
import CoreLocation
import Combine
import SwiftUI
import UserNotifications

struct StreetVisit: Codable, Identifiable {
    let id: UUID
    let streetName: String
    let crossStreet: String?
    let neighborhood: String?
    let borough: String?
    let factSnippet: String?
    let timestamp: Date
    let latitude: Double
    let longitude: Double

    init(
        streetName: String,
        crossStreet: String?,
        neighborhood: String?,
        borough: String?,
        factSnippet: String?,
        timestamp: Date,
        latitude: Double,
        longitude: Double
    ) {
        self.id = UUID()
        self.streetName = streetName
        self.crossStreet = crossStreet
        self.neighborhood = neighborhood
        self.borough = borough
        self.factSnippet = factSnippet
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
    }
}

struct WalkSession: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var visits: [StreetVisit]

    init(startedAt: Date, endedAt: Date? = nil, visits: [StreetVisit] = []) {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.visits = visits
    }
}

@MainActor
final class JourneyStore: ObservableObject {
    @Published var currentSession: WalkSession?
    @Published var sessions: [WalkSession] = []
    @Published var favorites: [StreetVisit] = []
    @Published var notificationsAuthorized = false

    private let sessionsKey = "walk_sessions_v1"
    private let favoritesKey = "favorite_streets_v1"
    private let lastNotifiedStreetKey = "last_notified_street_v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let stored = try? decoder.decode([WalkSession].self, from: data) {
            sessions = stored
        }

        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let stored = try? decoder.decode([StreetVisit].self, from: data) {
            favorites = stored
        }

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAuthorized = settings.authorizationStatus == .authorized
        }
    }

    var isJourneyActive: Bool {
        currentSession != nil
    }

    func startJourney() async {
        await requestNotificationPermissionIfNeeded()
        currentSession = WalkSession(startedAt: Date())
    }

    func stopJourney() {
        guard var session = currentSession else { return }
        session.endedAt = Date()
        sessions.insert(session, at: 0)
        currentSession = nil
        persistSessions()
    }

    func record(card: CardResponse, location: CLLocation) {
        guard var session = currentSession else { return }
        guard let streetName = card.canonical_street, !streetName.isEmpty else { return }
        guard card.mode == "NAMED_STREET" else { return }

        if session.visits.last?.streetName == streetName {
            return
        }

        let visit = StreetVisit(
            streetName: streetName,
            crossStreet: card.cross_street,
            neighborhood: card.neighborhood,
            borough: card.borough,
            factSnippet: card.did_you_know,
            timestamp: Date(),
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        session.visits.append(visit)
        currentSession = session
        notifyIfNeeded(for: visit)
    }

    func clearHistory() {
        sessions = []
        UserDefaults.standard.removeObject(forKey: sessionsKey)
    }

    func isFavorite(_ streetName: String) -> Bool {
        favorites.contains { $0.streetName.lowercased() == streetName.lowercased() }
    }

    func toggleFavorite(card: CardResponse, location: CLLocation) {
        let name = card.canonical_street ?? ""
        if let idx = favorites.firstIndex(where: { $0.streetName.lowercased() == name.lowercased() }) {
            favorites.remove(at: idx)
        } else {
            let visit = StreetVisit(
                streetName: name,
                crossStreet: card.cross_street,
                neighborhood: card.neighborhood,
                borough: card.borough,
                factSnippet: card.did_you_know,
                timestamp: Date(),
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            favorites.append(visit)
        }
        persistFavorites()
    }

    func removeFavorite(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        persistFavorites()
    }

    private func persistFavorites() {
        if let data = try? encoder.encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }

    private func persistSessions() {
        if let data = try? encoder.encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }

    private func requestNotificationPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized {
            notificationsAuthorized = true
            return
        }

        do {
            notificationsAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            notificationsAuthorized = false
        }
    }

    private func notifyIfNeeded(for visit: StreetVisit) {
        guard notificationsAuthorized else { return }

        let lastStreet = UserDefaults.standard.string(forKey: lastNotifiedStreetKey)
        if lastStreet == visit.streetName {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = visit.streetName
        if let factSnippet = visit.factSnippet, !factSnippet.isEmpty {
            content.body = factSnippet
        } else if let cross = visit.crossStreet, !cross.isEmpty {
            content.body = "Now near \(cross)"
        } else if let neighborhood = visit.neighborhood {
            content.body = "Now in \(neighborhood)"
        } else {
            content.body = "New street visited"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "street-\(visit.id.uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
        UserDefaults.standard.set(visit.streetName, forKey: lastNotifiedStreetKey)
    }
}
