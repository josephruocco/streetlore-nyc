import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    let journeyStore: JourneyStore

    @State private var page = 0

    private struct Page {
        let icon: String
        let title: String
        let text: String
    }

    private let pages: [Page] = [
        Page(
            icon: "signpost.right.and.left.fill",
            title: "Welcome to StreetLore",
            text: "Walk around NYC with the app open. It finds the street you're standing on and tells you the history behind its name."
        ),
        Page(
            icon: "location.circle.fill",
            title: "The Street card",
            text: "The first tab is live. It shows your street, the nearest cross street, the neighborhood, and the story of the name. Tap the heart to save a street you love."
        ),
        Page(
            icon: "map.fill",
            title: "The Map",
            text: "The Map tab shows every street with a story near you, so you can plan a walk toward the good ones."
        ),
        Page(
            icon: "figure.walk",
            title: "Journeys",
            text: "Start a journey to log every street of a walk as one trip. The app counts every street you ever explore, and can ping you the first time you set foot on a new one."
        ),
        Page(
            icon: "gearshape.fill",
            title: "Make it yours",
            text: "Settings has light and dark themes, bug reports, and this walkthrough if you ever want it again. That's everything. Go walk."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: pages[i].icon)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(Color(red: 0.06, green: 0.42, blue: 0.30))
                        Text(pages[i].title)
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text(pages[i].text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 32)
                        Spacer()
                        Spacer()
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    isPresented = false
                    Task { await journeyStore.requestNotificationPermissionIfNeeded() }
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Start walking")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.06, green: 0.42, blue: 0.30), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)

            Button("Skip") {
                isPresented = false
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .opacity(page < pages.count - 1 ? 1 : 0)
        }
        .background(Color(red: 0.92, green: 0.89, blue: 0.84).ignoresSafeArea())
    }
}
