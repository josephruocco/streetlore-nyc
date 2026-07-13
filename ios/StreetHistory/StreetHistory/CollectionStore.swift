import SwiftUI
import Combine

struct BoroughProgress: Identifiable {
    var id: String { borough }
    let borough: String
    let explored: Int
    let total: Int
    var fraction: Double { total == 0 ? 0 : Double(explored) / Double(total) }
}

struct NeighborhoodProgress: Identifiable {
    var id: String { neighborhood }
    let neighborhood: String
    let borough: String?
    let explored: Int
    let total: Int
    var isComplete: Bool { total > 0 && explored >= total }
    var fraction: Double { total == 0 ? 0 : Double(explored) / Double(total) }
}

/// Loads the storied-street catalog (the same /v1/facts/map list the Map tab
/// uses) and crosses it with the explored ledger to compute collection stats.
/// ponytail: reuses FactMapViewModel's disk cache key, so opening the Map and
/// this view share one cached download.
@MainActor
final class CollectionStore: ObservableObject {
    @Published var catalog: [FactMapItem] = []
    @Published var isLoading = false

    private let baseURL: String
    private static let cacheKey = "cachedMapFacts"

    init() {
        self.baseURL = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
            ?? "https://nyc-street-history.onrender.com"
    }

    func load() async {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let decoded = try? JSONDecoder().decode([FactMapItem].self, from: data) {
            catalog = decoded
            return
        }
        guard catalog.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var comps = URLComponents(string: "\(baseURL)/v1/facts/map")!
            comps.queryItems = [.init(name: "min_confidence", value: "0.0")]
            let (data, _) = try await URLSession.shared.data(from: comps.url!)
            catalog = try JSONDecoder().decode([FactMapItem].self, from: data)
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        } catch {
            // Silent: collection just stays empty until the network is back.
        }
    }

    var totalStoried: Int { catalog.count }

    func exploredCount(in explored: Set<String>) -> Int {
        catalog.filter { explored.contains($0.street_name.lowercased()) }.count
    }

    func boroughProgress(explored: Set<String>) -> [BoroughProgress] {
        var totals: [String: Int] = [:]
        var done: [String: Int] = [:]
        for item in catalog {
            guard let b = item.borough, !b.isEmpty else { continue }
            totals[b, default: 0] += 1
            if explored.contains(item.street_name.lowercased()) {
                done[b, default: 0] += 1
            }
        }
        return totals.keys.sorted().map {
            BoroughProgress(borough: $0, explored: done[$0] ?? 0, total: totals[$0] ?? 0)
        }
    }

    func neighborhoodProgress(explored: Set<String>) -> [NeighborhoodProgress] {
        var totals: [String: Int] = [:]
        var done: [String: Int] = [:]
        var boroughOf: [String: String?] = [:]
        for item in catalog {
            guard let n = item.neighborhood, !n.isEmpty else { continue }
            totals[n, default: 0] += 1
            boroughOf[n] = item.borough
            if explored.contains(item.street_name.lowercased()) {
                done[n, default: 0] += 1
            }
        }
        return totals.keys.map {
            NeighborhoodProgress(
                neighborhood: $0, borough: boroughOf[$0] ?? nil,
                explored: done[$0] ?? 0, total: totals[$0] ?? 0
            )
        }
        // completed first, then closest to done
        .sorted {
            if $0.isComplete != $1.isComplete { return $0.isComplete }
            return $0.fraction > $1.fraction
        }
    }

    func rareFindsExplored(explored: Set<String>) -> [FactMapItem] {
        catalog.filter {
            $0.rarity == "rare" && explored.contains($0.street_name.lowercased())
        }
    }
}
