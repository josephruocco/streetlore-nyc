import WidgetKit
import SwiftUI

// The widget has two states:
//   1. On a walk  — the app shares the street you're currently on (via an App
//      Group), and the widget shows that street's fact. "On a walk" means the
//      app updated your location within the last 45 minutes.
//   2. Otherwise  — a "Did you know?" fact, rotated from a bundled set so it
//      changes through the day with no network.

let appGroup = "group.com.josephruocco.StreetHistory"

struct StreetFact: Decodable {
    let street: String
    let fact: String
}

private let fallbackFact = StreetFact(
    street: "StreetLore",
    fact: "Walk any NYC street to discover the story behind its name."
)

private func allFacts() -> [StreetFact] {
    guard let url = Bundle.main.url(forResource: "widget_facts", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let facts = try? JSONDecoder().decode([StreetFact].self, from: data),
          !facts.isEmpty
    else { return [fallbackFact] }
    return facts
}

// Scatter the index so consecutive ticks feel random rather than sequential.
private func randomFact(tick: Int) -> StreetFact {
    let facts = allFacts()
    let scattered = (tick &* 2_654_435_761) % facts.count
    let i = ((scattered % facts.count) + facts.count) % facts.count
    return facts[i]
}

// The street the app last reported, if recent enough to count as "on a walk".
private func currentStreet() -> (street: String, fact: String, hood: String?)? {
    guard let d = UserDefaults(suiteName: appGroup),
          let street = d.string(forKey: "cur_street"), !street.isEmpty,
          let fact = d.string(forKey: "cur_fact"), !fact.isEmpty
    else { return nil }
    let ts = d.double(forKey: "cur_ts")
    guard ts > 0, Date().timeIntervalSince1970 - ts < 45 * 60 else { return nil }
    return (street, fact, d.string(forKey: "cur_hood"))
}

struct FactEntry: TimelineEntry {
    let date: Date
    let street: String
    let fact: String
    let hood: String?
    let onWalk: Bool
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> FactEntry {
        let f = allFacts().first ?? fallbackFact
        return FactEntry(date: Date(), street: f.street, fact: f.fact, hood: nil, onWalk: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (FactEntry) -> Void) {
        completion(entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FactEntry>) -> Void) {
        // On a walk, re-check every 10 min (the street changes / the walk ends).
        // Otherwise roll a fresh "Did you know?" every 2 hours.
        if let cur = currentStreet() {
            let entry = FactEntry(date: Date(), street: cur.street, fact: cur.fact,
                                  hood: cur.hood, onWalk: true)
            let next = Calendar.current.date(byAdding: .minute, value: 10, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(next)))
            return
        }
        let now = Date()
        let baseTick = Int(now.timeIntervalSince1970 / (2 * 3600))
        var entries: [FactEntry] = []
        for step in 0..<6 {
            if let d = Calendar.current.date(byAdding: .hour, value: step * 2, to: now) {
                let f = randomFact(tick: baseTick + step)
                entries.append(FactEntry(date: d, street: f.street, fact: f.fact, hood: nil, onWalk: false))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(for date: Date) -> FactEntry {
        if let cur = currentStreet() {
            return FactEntry(date: date, street: cur.street, fact: cur.fact, hood: cur.hood, onWalk: true)
        }
        let f = randomFact(tick: Int(date.timeIntervalSince1970 / (2 * 3600)))
        return FactEntry(date: date, street: f.street, fact: f.fact, hood: nil, onWalk: false)
    }
}

private let cream = Color(red: 0.957, green: 0.945, blue: 0.902)  // #F4F1E6
private let ink   = Color(red: 0.137, green: 0.125, blue: 0.106)  // #23201B
private let green = Color(red: 0.133, green: 0.318, blue: 0.235)  // #22513C

struct StreetLoreWidgetView: View {
    var entry: FactEntry
    @Environment(\.widgetFamily) private var family

    private var isSmall: Bool { family == .systemSmall }

    private var eyebrow: String {
        entry.onWalk ? "ABOUT THIS STREET" : "DID YOU KNOW?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: entry.onWalk ? "figure.walk" : "signpost.right.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(green)

            Text(entry.street)
                .font(.system(size: isSmall ? 17 : 21, weight: .bold, design: .serif))
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(entry.fact)
                .font(.system(size: isSmall ? 11 : 13))
                .foregroundStyle(ink.opacity(0.82))
                .lineLimit(isSmall ? 4 : 6)
                .lineSpacing(1)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(cream, for: .widget)
    }
}

struct StreetLoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StreetLoreWidget", provider: Provider()) { entry in
            StreetLoreWidgetView(entry: entry)
        }
        .configurationDisplayName("Street Lore")
        .description("The street you're walking, or a Did you know? when you're not.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct StreetLoreWidgetBundle: WidgetBundle {
    var body: some Widget {
        StreetLoreWidget()
    }
}
