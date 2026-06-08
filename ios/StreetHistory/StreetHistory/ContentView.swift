import SwiftUI
import CoreLocation
import Combine

struct ContentView: View {
    @StateObject private var lm = LocationManager()
    @StateObject private var vm = CardViewModel()
    @ObservedObject var journeyStore: JourneyStore

    @State private var fetchTask: Task<Void, Never>?
    @State private var isUpdating = false
    @State private var showJourneyPrompt = false
    @State private var showHistory = false
    @State private var showStreetContext = false
    @State private var showExploreBrowser = false
    @State private var selectedNeighborhoodGuide: NeighborhoodGuide?

    private var isAuthorized: Bool {
        lm.status == .authorizedWhenInUse || lm.status == .authorizedAlways
    }

    private var placeLine: String? {
        let parts = [vm.card?.neighborhood, vm.card?.borough].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    var body: some View {
        ZStack {
            Color(red: 0.92, green: 0.89, blue: 0.84)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    statusBar
                    mainCard
                    journeyCards
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }

        .onChange(of: lm.significantLocation) { _, loc in
            guard isAuthorized, let loc else { return }

            isUpdating = true
            fetchTask?.cancel()
            fetchTask = Task {
                defer { isUpdating = false }
                await vm.update(for: loc)
                if let card = vm.card {
                    journeyStore.record(card: card, location: loc)
                }
                if !journeyStore.isJourneyActive && !showJourneyPrompt {
                    showJourneyPrompt = true
                }
            }
        }
        .onChange(of: lm.status) { _, _ in
            if isAuthorized {
                lm.requestPermissionAndStart()
            }
        }
        .onAppear {
            if isAuthorized {
                lm.requestPermissionAndStart()
            }
        }
        .alert("Start a journey?", isPresented: $showJourneyPrompt) {
            Button("Not now", role: .cancel) {}
            Button("Start") {
                Task {
                    await journeyStore.startJourney()
                }
            }
        } message: {
            Text("If you start a journey, the app will log the named streets you visit and notify you when you reach a new one.")
        }
        .sheet(isPresented: $showHistory) {
            JourneyHistoryView(journeyStore: journeyStore)
        }
        .fullScreenCover(isPresented: $showStreetContext) {
            if let card = vm.card {
                StreetContextPage(card: card)
            }
        }
        .sheet(isPresented: $showExploreBrowser) {
            NeighborhoodGuideBrowserView()
        }
        .sheet(item: $selectedNeighborhoodGuide) { guide in
            NeighborhoodGuideDetailView(guide: guide)
        }
    }

    private var statusBar: some View {
        HStack {
            if !isAuthorized {
                Button("Enable Location") {
                    lm.requestPermissionAndStart()
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.82), in: Capsule())
                .foregroundStyle(.white)
            } else {
                Label(isUpdating ? "Updating" : "Live", systemImage: isUpdating ? "location.circle.fill" : "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isUpdating ? Color(red: 0.42, green: 0.27, blue: 0.17) : Color(red: 0.12, green: 0.22, blue: 0.28))
            }

            Spacer()

            if isAuthorized {
                Button {
                    showExploreBrowser = true
                } label: {
                    Image(systemName: "map")
                        .font(.headline)
                        .foregroundStyle(Color.black.opacity(0.72))
                }

                if journeyStore.isJourneyActive, let session = journeyStore.currentSession {
                    Menu {
                        Button("Stop journey", role: .destructive) {
                            journeyStore.stopJourney()
                        }
                        Button("Journey history") {
                            showHistory = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "figure.walk")
                                .font(.caption.weight(.bold))
                            Text("\(session.visits.count)")
                                .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.82), in: Capsule())
                        .foregroundStyle(.white)
                    }
                } else {
                    Menu {
                        Button("Start journey") {
                            Task {
                                await journeyStore.startJourney()
                            }
                        }
                        Button("Journey history") {
                            showHistory = true
                        }
                    } label: {
                        Image(systemName: "figure.walk.circle")
                            .font(.headline)
                            .foregroundStyle(Color.black.opacity(0.72))
                    }
                }
            }

            if !isAuthorized {
                Text(statusText(lm.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let lastUpdated = vm.lastUpdatedText {
                Text(lastUpdated)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 2)
    }

    private var mainCard: some View {
        Group {
            if let card = vm.card {
                VStack(alignment: .leading, spacing: 22) {
                    heroSection(card)
                    factSection(card)
                    if let err = vm.errorText {
                        inlineError(err)
                    }
                }
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(red: 0.985, green: 0.975, blue: 0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            } else if !isAuthorized {
                emptyState(
                    title: "Turn on location",
                    body: "The app needs your location to match your street to nearby history.",
                    systemImage: "location.slash"
                )
            } else {
                emptyState(
                    title: "Finding your street",
                    body: "Waiting for a stable location update before fetching a card.",
                    systemImage: "location.magnifyingglass"
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.card?.canonical_street ?? "")
    }

    @ViewBuilder
    private var journeyCards: some View {
        if journeyStore.isJourneyActive,
           let session = journeyStore.currentSession,
           session.visits.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "figure.walk")
                        .font(.caption.weight(.bold))
                    Text("This walk — \(session.visits.count) streets")
                        .font(.caption.weight(.bold))
                    Spacer()
                }
                .foregroundStyle(Color(red: 0.40, green: 0.24, blue: 0.14))

                ForEach(session.visits.dropLast().reversed()) { visit in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(visit.streetName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.black.opacity(0.88))

                        if let cross = visit.crossStreet, !cross.isEmpty {
                            Text("near \(cross)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let fact = visit.factSnippet, !fact.isEmpty,
                           !fact.contains("still being researched") {
                            Text(fact)
                                .font(.caption)
                                .foregroundStyle(Color.black.opacity(0.7))
                                .lineLimit(2)
                                .lineSpacing(2)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(red: 0.985, green: 0.975, blue: 0.95))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func heroSection(_ card: CardResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            let hasHeroImage = historyImageURL(card) != nil || historyImageSourceURL(card) != nil

            if hasHeroImage {
                HistoryImageView(
                    imageURL: historyImageURL(card),
                    wikipediaSourceURL: historyImageSourceURL(card)
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            }

            if let placeLine {
                let guide = card.neighborhood.flatMap { NeighborhoodGuideStore.neighborhood(named: $0) }
                Group {
                    if let guide {
                        Button {
                            selectedNeighborhoodGuide = guide
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(red: 0.40, green: 0.24, blue: 0.14))
                                    .frame(width: 7, height: 7)
                                Text(placeLine)
                                    .font(.footnote.weight(.semibold))
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(Color(red: 0.40, green: 0.24, blue: 0.14))
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(red: 0.40, green: 0.24, blue: 0.14))
                                .frame(width: 7, height: 7)
                            Text(placeLine)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color(red: 0.40, green: 0.24, blue: 0.14))
                        }
                    }
                }
            }

            HStack(alignment: .top) {
                Text(card.canonical_street ?? "Unknown street")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                if let streetName = card.canonical_street, !streetName.isEmpty {
                    Button {
                        if let loc = lm.significantLocation {
                            journeyStore.toggleFavorite(card: card, location: loc)
                        }
                    } label: {
                        Image(systemName: journeyStore.isFavorite(streetName) ? "heart.fill" : "heart")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(journeyStore.isFavorite(streetName)
                                ? Color(red: 0.75, green: 0.22, blue: 0.17)
                                : Color.black.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let cross = card.cross_street, !cross.isEmpty {
                labelChip(title: "Crossing", value: cross)
            }
        }
    }

    private func factSection(_ card: CardResponse) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            let historyParts = splitHistory(card)

            HStack(alignment: .firstTextBaseline) {
                Text("History")
                    .font(.headline.weight(.bold))
            }

            if let deck = historyParts.deck {
                Text(deck)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.40, green: 0.24, blue: 0.14))
                    .lineSpacing(3)
                    .frame(maxWidth: 305, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let body = historyParts.body {
                Text(body)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(Color.black.opacity(0.95))
                    .lineSpacing(6)
                    .frame(maxWidth: 305, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No street-name history loaded yet.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(historySource(card)?.label == nil ? "Coverage note" : "Source")
                        .font(.caption.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)

                    if let source = historySource(card), let label = source.label, !label.isEmpty {
                        Text(label)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.84))
                    } else {
                        Text("This entry still needs a proper namesake source.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(0.72))
                    }
                }

                Spacer()

                if let source = historySource(card),
                   let urlString = source.url,
                   let url = URL(string: urlString),
                   !urlString.isEmpty {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Text("Open")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Color(red: 0.40, green: 0.24, blue: 0.14))
                    }
                }
            }

            if !uniqueNearby(card.nearby).isEmpty {
                Button {
                    showStreetContext = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Street context")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Color.black.opacity(0.88))
                            Text("Nearby places if you want extra context.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(uniqueNearby(card.nearby).count)")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.05), in: Capsule())
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(Color(red: 0.94, green: 0.92, blue: 0.87), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(
            Color(red: 0.95, green: 0.92, blue: 0.84),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func inlineError(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .padding(12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func emptyState(title: String, body: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color(red: 0.42, green: 0.27, blue: 0.17))

            Text(title)
                .font(.title2.weight(.bold))

            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(3)

            if let err = vm.errorText {
                inlineError(err)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.90))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func labelChip(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.black))
                .tracking(0.9)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.86))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(red: 0.93, green: 0.92, blue: 0.90), in: Capsule())
    }

    private func categoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "park":
            return Color(red: 0.21, green: 0.46, blue: 0.27)
        case "transit":
            return Color(red: 0.17, green: 0.33, blue: 0.58)
        case "food":
            return Color(red: 0.61, green: 0.24, blue: 0.19)
        case "landmark":
            return Color(red: 0.50, green: 0.33, blue: 0.11)
        default:
            return .gray
        }
    }

    private func prettyCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "park":
            return "Park"
        case "transit":
            return "Transit"
        case "food":
            return "Food"
        case "landmark":
            return "Landmark"
        default:
            return category.capitalized
        }
    }

    private func distanceLabel(_ meters: Int) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km away", Double(meters) / 1000.0)
        }
        return "\(meters)m away"
    }

    private func modeLabel(_ mode: String) -> String {
        switch mode {
        case "NAMED_STREET":
            return "Named Street"
        case "NUMBERED_STREET":
            return "Numbered Street"
        default:
            return mode.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func historyBodyText(_ card: CardResponse) -> String? {
        let rawText = card.history?.blurb ?? card.history_blurb ?? card.did_you_know
        guard var text = rawText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }

        if let neighborhood = card.neighborhood?.trimmingCharacters(in: .whitespacesAndNewlines),
           !neighborhood.isEmpty {
            let redundantPrefix = "You're in \(neighborhood). "
            if text.hasPrefix(redundantPrefix) {
                text.removeFirst(redundantPrefix.count)
            }
        }

        if text == "Check nearby landmarks for context." {
            return "Street-name history is still being added for this location."
        }

        if text.hasPrefix("Check nearby landmarks for context.") {
            return "Street-name history is still being added for this location."
        }

        return text
    }

    private func splitHistory(_ card: CardResponse) -> (deck: String?, body: String?) {
        guard let text = historyBodyText(card), !text.isEmpty else {
            return (nil, nil)
        }

        let sentences = text
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let first = sentences.first else {
            return (nil, text)
        }

        if sentences.count == 1 {
            return (nil, text)
        }

        let deck = first + "."
        let remainder = sentences.dropFirst().joined(separator: ". ")
        let body = remainder.isEmpty ? text : remainder + "."
        return (deck, body)
    }

    private func historyImageURL(_ card: CardResponse) -> String? {
        card.history?.image_url ?? card.image_url
    }

    private func historyImageSourceURL(_ card: CardResponse) -> String? {
        card.history?.image_source_url ?? card.image_source_url ?? historySource(card)?.url
    }

    private func historySource(_ card: CardResponse) -> FactSource? {
        card.history?.source ?? card.sources?.first
    }

    private var historyImageFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.05))
            Image(systemName: "photo")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func uniqueNearby(_ items: [NearbyItem]) -> [NearbyItem] {
        var seen = Set<String>()
        var result: [NearbyItem] = []

        for item in items {
            let key = "\(item.name.lowercased())|\(item.category.lowercased())"
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(item)
        }

        return result
    }

    private func statusText(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .authorizedAlways: return "authorizedAlways"
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }
}

private struct StreetContextPage: View {
    let card: CardResponse
    @Environment(\.dismiss) private var dismiss

    private func categoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "park":
            return Color(red: 0.21, green: 0.46, blue: 0.27)
        case "transit":
            return Color(red: 0.17, green: 0.33, blue: 0.58)
        case "food":
            return Color(red: 0.61, green: 0.24, blue: 0.19)
        case "landmark":
            return Color(red: 0.50, green: 0.33, blue: 0.11)
        default:
            return .gray
        }
    }

    private func prettyCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "park":
            return "Park"
        case "transit":
            return "Transit"
        case "food":
            return "Food"
        case "landmark":
            return "Landmark"
        default:
            return category.capitalized
        }
    }

    private func distanceLabel(_ meters: Int) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km away", Double(meters) / 1000.0)
        }
        return "\(meters)m away"
    }

    private func uniqueNearby(_ items: [NearbyItem]) -> [NearbyItem] {
        var seen = Set<String>()
        var result: [NearbyItem] = []

        for item in items {
            let key = "\(item.name.lowercased())|\(item.category.lowercased())"
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(item)
        }

        return result
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(uniqueNearby(card.nearby)) { item in
                        HStack(alignment: .top, spacing: 14) {
                            Circle()
                                .fill(categoryColor(item.category))
                                .frame(width: 10, height: 10)
                                .padding(.top, 7)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.name)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(Color.black.opacity(0.92))

                                HStack(spacing: 8) {
                                    Text(prettyCategory(item.category))
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(categoryColor(item.category).opacity(0.14), in: Capsule())
                                        .foregroundStyle(categoryColor(item.category))

                                    Text(distanceLabel(item.distance_m))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                } footer: {
                    Text("Nearby places are secondary context. The main card stays focused on the street name itself.")
                }
            }
            .navigationTitle("Street Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct WikipediaSummaryResponse: Decodable {
    struct Thumbnail: Decodable {
        let source: String
    }

    let thumbnail: Thumbnail?
}

private struct HistoryImageView: View {
    let imageURL: String?
    let wikipediaSourceURL: String?

    @State private var resolvedWikipediaThumbnailURL: String?
    @State private var hasAttemptedResolution = false

    var body: some View {
        Group {
            if let explicitURL = imageURL, let url = URL(string: explicitURL) {
                AsyncImage(url: url) { phase in
                    imagePhaseView(phase)
                }
            } else if let resolvedURL = resolvedWikipediaThumbnailURL, let url = URL(string: resolvedURL) {
                AsyncImage(url: url) { phase in
                    imagePhaseView(phase)
                }
            } else if wikipediaSummaryURL != nil && !hasAttemptedResolution {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.05))
                    ProgressView()
                }
                .task {
                    await resolveWikipediaThumbnail()
                }
            } else {
                EmptyView()
            }
        }
    }

    private var wikipediaSummaryURL: URL? {
        guard let wikipediaSourceURL,
              let url = URL(string: wikipediaSourceURL),
              let host = url.host,
              host.contains("wikipedia.org") else { return nil }

        let title = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        guard !title.isEmpty else { return nil }
        let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        return URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(encodedTitle)")
    }

    private func imagePhaseView(_ phase: AsyncImagePhase) -> some View {
        Group {
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure(_):
                historyImageFallback
            case .empty:
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.05))
                    ProgressView()
                }
            @unknown default:
                historyImageFallback
            }
        }
    }

    @MainActor
    private func resolveWikipediaThumbnail() async {
        guard !hasAttemptedResolution else { return }
        hasAttemptedResolution = true

        guard let summaryURL = wikipediaSummaryURL else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: summaryURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let summary = try JSONDecoder().decode(WikipediaSummaryResponse.self, from: data)
            resolvedWikipediaThumbnailURL = summary.thumbnail?.source
        } catch {
            resolvedWikipediaThumbnailURL = nil
        }
    }

    private var historyImageFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.05))
            Image(systemName: "photo")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct JourneyHistoryView: View {
    @ObservedObject var journeyStore: JourneyStore
    @Environment(\.dismiss) private var dismiss

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                if journeyStore.sessions.isEmpty {
                    Text("No walks logged yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(journeyStore.sessions) { session in
                        Section {
                            ForEach(session.visits) { visit in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(visit.streetName)
                                        .font(.headline)
                                    Text(dateFormatter.string(from: visit.timestamp))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let cross = visit.crossStreet, !cross.isEmpty {
                                        Text("Near \(cross)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let fact = visit.factSnippet, !fact.isEmpty {
                                        Text(fact)
                                            .font(.subheadline)
                                            .lineLimit(3)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            Text(sessionTitle(session))
                        }
                    }
                }
            }
            .navigationTitle("Walk History")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                if !journeyStore.sessions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") {
                            journeyStore.clearHistory()
                        }
                    }
                }
            }
        }
    }

    private func sessionTitle(_ session: WalkSession) -> String {
        let start = dateFormatter.string(from: session.startedAt)
        if let endedAt = session.endedAt {
            return "\(start) to \(dateFormatter.string(from: endedAt))"
        }
        return start
    }
}
