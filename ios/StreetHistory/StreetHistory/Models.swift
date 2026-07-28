import Foundation

struct FactSource: Codable {
    let label: String?
    let url: String?
}

struct HistoryEntry: Codable {
    let namesake: String?
    let blurb: String?
    let image_url: String?
    let image_source_url: String?
    let source: FactSource?
}

struct NearbyItem: Codable, Identifiable {
    // Using a generated UUID keeps SwiftUI happy; server doesn't need to send an id.
    let id: UUID
    let name: String
    let category: String
    let distance_m: Int

    init(name: String, category: String, distance_m: Int) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.distance_m = distance_m
    }

    // Custom decode to generate id on decode
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try c.decode(String.self, forKey: .name)
        self.category = try c.decode(String.self, forKey: .category)
        self.distance_m = try c.decode(Int.self, forKey: .distance_m)
    }

    enum CodingKeys: String, CodingKey {
        case name, category, distance_m
    }
}

struct CardResponse: Codable {
    let canonical_street: String?
    let cross_street: String?
    let borough: String?
    let neighborhood: String?
    let mode: String
    let history: HistoryEntry?
    let namesake: String?
    let history_blurb: String?
    let image_url: String?
    let image_source_url: String?
    let did_you_know: String?
    let fact_count: Int?      // how many rotating facts this street has
    let nearby: [NearbyItem]
    let sources: [FactSource]?

    // Optional extras (safe if server doesn't send them)
    let snap_distance_m: Int?
    let fact_source_label: String?
    let fact_source_url: String?
    let fact_confidence: Double?
}
