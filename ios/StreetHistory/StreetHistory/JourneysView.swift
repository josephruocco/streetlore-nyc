import SwiftUI

struct JourneysView: View {
    @ObservedObject var journeyStore: JourneyStore
    @StateObject private var collection = CollectionStore()

    private let accent = Color(red: 0.40, green: 0.24, blue: 0.14)
    private let green = Color(red: 0.0, green: 0.42, blue: 0.30)

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var explored: Set<String> { journeyStore.exploredStreets }

    var body: some View {
        NavigationStack {
            List {
                collectionHeader

                boroughSection

                let badges = completedNeighborhoods
                if !badges.isEmpty {
                    Section("Neighborhood badges") {
                        ForEach(badges) { n in
                            badgeRow(n)
                        }
                    }
                }

                let inProgress = nearestNeighborhoods
                if !inProgress.isEmpty {
                    Section("Closest to complete") {
                        ForEach(inProgress) { n in
                            neighborhoodProgressRow(n)
                        }
                    }
                }

                let rares = collection.rareFindsExplored(explored: explored)
                if !rares.isEmpty {
                    Section {
                        ForEach(rares) { item in
                            Label(prettyName(item.street_name), systemImage: "sparkles")
                                .foregroundStyle(green)
                        }
                    } header: {
                        Text("Rare finds")
                    } footer: {
                        Text("Tiny courts, lanes, and walks most people never set foot on.")
                    }
                }

                journeySection
                pastWalksSection
            }
            .navigationTitle("Journeys")
            .toolbar {
                if !journeyStore.sessions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") { journeyStore.clearHistory() }
                    }
                }
            }
            .task { await collection.load() }
        }
    }

    // MARK: - Collection header

    private var collectionHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: "signpost.right.and.left.fill")
                        .font(.title)
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        if collection.totalStoried > 0 {
                            Text("\(journeyStore.streetsExploredCount) of \(collection.totalStoried)")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                        } else {
                            Text("\(journeyStore.streetsExploredCount)")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                        }
                        Text("storied streets explored")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if journeyStore.currentStreak > 0 {
                    Label("\(journeyStore.currentStreak) day streak", systemImage: "flame.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                ShareLink(
                    item: shareImage,
                    preview: SharePreview("My StreetLore progress", image: shareImage)
                ) {
                    Label("Share progress", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.vertical, 6)
        } footer: {
            Text("Every named street you pass with the app open counts, journey or not.")
        }
    }

    private var boroughSection: some View {
        let bars = collection.boroughProgress(explored: explored)
        return Group {
            if !bars.isEmpty {
                Section("By borough") {
                    ForEach(bars) { b in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(b.borough).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(b.explored)/\(b.total)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: b.fraction)
                                .tint(green)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - Neighborhoods

    private var completedNeighborhoods: [NeighborhoodProgress] {
        collection.neighborhoodProgress(explored: explored).filter { $0.isComplete }
    }

    private var nearestNeighborhoods: [NeighborhoodProgress] {
        collection.neighborhoodProgress(explored: explored)
            .filter { !$0.isComplete && $0.explored > 0 }
            .prefix(6)
            .map { $0 }
    }

    private func badgeRow(_ n: NeighborhoodProgress) -> some View {
        HStack {
            Image(systemName: "rosette")
                .foregroundStyle(green)
            VStack(alignment: .leading) {
                Text(n.neighborhood).font(.headline)
                Text("All \(n.total) streets explored")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            ShareLink(
                item: badgeImage(n),
                preview: SharePreview("\(n.neighborhood) complete", image: badgeImage(n))
            ) {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    private func neighborhoodProgressRow(_ n: NeighborhoodProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(n.neighborhood).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(n.explored)/\(n.total)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            ProgressView(value: n.fraction).tint(accent)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Journeys

    @ViewBuilder
    private var journeySection: some View {
        if let session = journeyStore.currentSession, !session.visits.isEmpty {
            Section {
                ForEach(session.visits.reversed()) { visit in visitRow(visit) }
            } header: {
                Text("Current walk")
            } footer: {
                Text("Journeys record automatically as you walk. A new one starts after a break.")
            }
        }
    }

    @ViewBuilder
    private var pastWalksSection: some View {
        if journeyStore.sessions.isEmpty && !journeyStore.isJourneyActive {
            Section("Past walks") {
                Text("No walks logged yet.").foregroundStyle(.secondary)
            }
        } else {
            ForEach(journeyStore.sessions) { session in
                Section(sessionTitle(session)) {
                    ForEach(session.visits) { visit in visitRow(visit) }
                }
            }
        }
    }

    private func visitRow(_ visit: StreetVisit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let crossing = visit.boroughCrossing {
                Text(crossing)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(green.opacity(0.12), in: Capsule())
            }
            Text(visit.streetName).font(.headline)
            Text(dateFormatter.string(from: visit.timestamp))
                .font(.caption).foregroundStyle(.secondary)
            if let cross = visit.crossStreet, !cross.isEmpty {
                Text("Near \(cross)").font(.caption).foregroundStyle(.secondary)
            }
            if let fact = visit.factSnippet, !fact.isEmpty,
               !fact.contains("still being researched") {
                Text(fact).font(.subheadline).lineLimit(3)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Sharing

    private var shareImage: Image {
        let card = ShareCard(
            headline: "\(journeyStore.streetsExploredCount)",
            subhead: journeyStore.streetsExploredCount == 1 ? "street explored" : "streets explored",
            footnote: collection.totalStoried > 0
                ? "of \(collection.totalStoried) storied NYC streets" : nil
        )
        return Image(uiImage: card.rendered() ?? UIImage())
    }

    private func badgeImage(_ n: NeighborhoodProgress) -> Image {
        let card = ShareCard(
            headline: n.neighborhood,
            subhead: "fully explored",
            footnote: "All \(n.total) storied streets\(n.borough.map { " in \($0)" } ?? "")"
        )
        return Image(uiImage: card.rendered() ?? UIImage())
    }

    // MARK: - Helpers

    private func prettyName(_ name: String) -> String {
        name.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }

    private func sessionTitle(_ session: WalkSession) -> String {
        let start = dateFormatter.string(from: session.startedAt)
        if let endedAt = session.endedAt {
            return "\(start) to \(dateFormatter.string(from: endedAt))"
        }
        return start
    }
}
