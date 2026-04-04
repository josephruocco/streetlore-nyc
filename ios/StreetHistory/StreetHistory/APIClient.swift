import Foundation

final class APIClient {
    private let baseURL: String

    // 20s timeout so a cold Render start fails fast and the retry loop kicks in.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    init() {
        self.baseURL = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String
            ?? "https://nyc-street-history.onrender.com"
    }

    func fetchCard(lat: Double, lon: Double, acc: Double) async throws -> CardResponse {
        guard var comps = URLComponents(string: "\(baseURL)/v1/card") else {
            throw URLError(.badURL)
        }
        comps.queryItems = [
            .init(name: "lat", value: "\(lat)"),
            .init(name: "lon", value: "\(lon)"),
            .init(name: "acc", value: "\(acc)")
        ]
        guard let url = comps.url else {
            throw URLError(.badURL)
        }

        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(CardResponse.self, from: data)
    }
}
