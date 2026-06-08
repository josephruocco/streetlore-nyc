import SwiftUI

struct FavoritesView: View {
    @ObservedObject var journeyStore: JourneyStore

    var body: some View {
        NavigationStack {
            Group {
                if journeyStore.favorites.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "heart.slash")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(Color(red: 0.42, green: 0.27, blue: 0.17))

                        Text("No favorites yet")
                            .font(.title3.weight(.bold))

                        Text("Tap the heart on any street card to save it here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.92, green: 0.89, blue: 0.84).ignoresSafeArea())
                } else {
                    List {
                        ForEach(journeyStore.favorites) { visit in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(visit.streetName)
                                    .font(.headline.weight(.bold))

                                if let neighborhood = visit.neighborhood {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(Color(red: 0.40, green: 0.24, blue: 0.14))
                                            .frame(width: 6, height: 6)
                                        Text(neighborhood)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Color(red: 0.40, green: 0.24, blue: 0.14))
                                    }
                                }

                                if let fact = visit.factSnippet, !fact.isEmpty,
                                   !fact.contains("still being researched") {
                                    Text(fact)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                        .lineSpacing(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in
                            journeyStore.removeFavorite(at: offsets)
                        }
                    }
                }
            }
            .navigationTitle("Favorites")
        }
    }
}
