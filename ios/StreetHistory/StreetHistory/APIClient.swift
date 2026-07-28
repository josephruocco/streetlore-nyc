import Foundation

final class APIClient {
    private let baseURL: String

    init() {
        self.baseURL = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
            ?? "https://nyc-street-history.onrender.com"
    }

    func fetchCard(lat: Double, lon: Double, acc: Double, rotate: Int = 0) async throws -> CardResponse {
        var comps = URLComponents(string: "\(baseURL)/v1/card")!
        comps.queryItems = [
            .init(name: "lat", value: "\(lat)"),
            .init(name: "lon", value: "\(lon)"),
            .init(name: "acc", value: "\(acc)"),
            .init(name: "rotate", value: "\(rotate)")
        ]
        let url = comps.url!

        let (data, resp) = try await URLSession.shared.data(from: url)
        let http = resp as! HTTPURLResponse
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(CardResponse.self, from: data)
    }
}
