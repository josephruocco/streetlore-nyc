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

    /// First time each named street was ever seen, lowercased name -> date.
    /// Grows whether or not a journey is active, so "streets explored" and
    /// streaks keep counting on any walk.
    @Published private(set) var firstSeen: [String: Date] = [:]

    var exploredStreets: Set<String> { Set(firstSeen.keys) }

    private let sessionsKey = "walk_sessions_v1"
    private let favoritesKey = "favorite_streets_v1"
    private let lastNotifiedStreetKey = "last_notified_street_v1"
    private let exploredKey = "explored_streets_v1"
    private let firstSeenKey = "explored_first_seen_v1"
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

        if let data = UserDefaults.standard.data(forKey: firstSeenKey),
           let stored = try? decoder.decode([String: Date].self, from: data) {
            firstSeen = stored
        } else {
            // migrate the old name-only ledger (and any pre-ledger walks) to
            // dated entries. We lack the real dates, so backfill to a fixed past
            // day; only streaks from today forward matter.
            let seed = Date(timeIntervalSince1970: 0)
            var migrated: [String: Date] = [:]
            for name in UserDefaults.standard.stringArray(forKey: exploredKey) ?? [] {
                migrated[name] = seed
            }
            for visit in sessions.flatMap({ $0.visits }) {
                migrated[visit.streetName.lowercased()] = visit.timestamp
            }
            firstSeen = migrated
            persistFirstSeen()
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

    var streetsExploredCount: Int {
        firstSeen.count
    }

    /// Consecutive days, counting back from today, on which at least one
    /// new street was discovered. Backfilled (epoch) entries don't count.
    var currentStreak: Int {
        let cal = Calendar.current
        let days = Set(
            firstSeen.values
                .filter { $0.timeIntervalSince1970 > 86_400 }
                .map { cal.startOfDay(for: $0) }
        )
        guard !days.isEmpty else { return 0 }

        var cursor = cal.startOfDay(for: Date())
        // allow the streak to be "alive" if today has no new street yet but
        // yesterday did.
        if !days.contains(cursor) {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
            if !days.contains(cursor) { return 0 }
        }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    func record(card: CardResponse, location: CLLocation) {
        guard let streetName = card.canonical_street, !streetName.isEmpty else { return }
        guard card.mode == "NAMED_STREET" else { return }

        let key = streetName.lowercased()
        let firstEver = firstSeen[key] == nil
        if firstEver {
            firstSeen[key] = Date()
            persistFirstSeen()
        }

        guard var session = currentSession else {
            if firstEver {
                notifyFirstVisit(streetName: streetName, card: card)
            }
            return
        }

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
        notifyIfNeeded(for: visit, firstEver: firstEver)
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

    private func persistFirstSeen() {
        if let data = try? encoder.encode(firstSeen) {
            UserDefaults.standard.set(data, forKey: firstSeenKey)
        }
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

    func requestNotificationPermissionIfNeeded() async {
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

    private func notifyFirstVisit(streetName: String, card: CardResponse) {
        guard notificationsAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "New street: \(streetName)"
        if let fact = card.did_you_know, !fact.isEmpty, !fact.contains("still being researched") {
            content.body = fact
        } else {
            content.body = "You've never walked this one before."
        }
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "first-\(UUID().uuidString)", content: content, trigger: nil)
        )
    }

    private func notifyIfNeeded(for visit: StreetVisit, firstEver: Bool = false) {
        guard notificationsAuthorized else { return }

        let lastStreet = UserDefaults.standard.string(forKey: lastNotifiedStreetKey)
        if lastStreet == visit.streetName {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = firstEver ? "New street: \(visit.streetName)" : visit.streetName
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
