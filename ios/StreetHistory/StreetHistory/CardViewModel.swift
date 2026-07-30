import Foundation
import Combine
import CoreLocation
import WidgetKit

@MainActor
final class CardViewModel: ObservableObject {
    @Published var card: CardResponse?
    @Published var errorText: String?
    @Published var lastUpdatedAt: Date?

    private let api = APIClient()
    private var lastFetchTime: Date = .distantPast

    private let cacheKey = "last_card_v2"
    private let visitsKey = "street_visits_v1"

    // Rotation: each street remembers how many times you've walked it, so a new
    // fact surfaces per arrival. The index holds steady while you linger.
    private var streetVisits: [String: Int]
    private var currentStreet: String?
    private var currentRotate: Int = 0

    init() {
        streetVisits = UserDefaults.standard.dictionary(forKey: visitsKey) as? [String: Int] ?? [:]
        // Load cached card on startup
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(CardResponse.self, from: data) {
            self.card = cached
        }
    }

    var lastUpdatedText: String? {
        guard let lastUpdatedAt else { return nil }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: lastUpdatedAt, relativeTo: Date()))"
    }

    func update(for location: CLLocation) async {
        let now = Date()
        if now.timeIntervalSince(lastFetchTime) < 2.0 { return }
        lastFetchTime = now

        do {
            let acc = max(location.horizontalAccuracy, 10)
            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude

            var res = try await api.fetchCard(lat: lat, lon: lon, acc: acc, rotate: currentRotate)

            // Arrived on a different street? Advance its fact and refetch so the
            // shown fact matches the new rotation index (first fetch used the
            // previous street's index).
            if let street = res.canonical_street, street != currentStreet {
                let visits = (streetVisits[street] ?? 0) + 1
                streetVisits[street] = visits
                UserDefaults.standard.set(streetVisits, forKey: visitsKey)
                currentStreet = street
                currentRotate = visits - 1   // 1st walk shows fact #0 (name origin)

                if let count = res.fact_count, count > 1 {
                    res = try await api.fetchCard(lat: lat, lon: lon, acc: acc, rotate: currentRotate)
                }
            }

            card = res
            errorText = nil
            lastUpdatedAt = now
            persist(res)
            shareWithWidget(res)
        } catch {
            // Keep cached card; show error
            errorText = error.localizedDescription
        }
    }

    private func persist(_ card: CardResponse) {
        if let data = try? JSONEncoder().encode(card) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    // Hand the current street to the widget via the shared App Group, then nudge
    // WidgetKit to refresh. The widget treats a recent write as "on a walk".
    private func shareWithWidget(_ card: CardResponse) {
        guard let d = UserDefaults(suiteName: "group.com.josephruocco.StreetHistory") else { return }
        d.set(card.canonical_street, forKey: "cur_street")
        d.set(card.did_you_know, forKey: "cur_fact")
        d.set(card.neighborhood, forKey: "cur_hood")
        d.set(Date().timeIntervalSince1970, forKey: "cur_ts")
        WidgetCenter.shared.reloadTimelines(ofKind: "StreetLoreWidget")
    }
}
