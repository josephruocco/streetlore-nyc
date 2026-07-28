import WidgetKit
import SwiftUI

// A curated street name story, one shown per day. The set is bundled as
// widget_facts.json so the widget renders instantly with no network or
// location. The daily pick is deterministic (days since epoch mod count),
// so every device shows the same street on the same day and it changes at
// midnight.

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

private func factForDay(_ date: Date) -> StreetFact {
    let facts = allFacts()
    let day = Int(date.timeIntervalSince1970 / 86_400)
    let i = ((day % facts.count) + facts.count) % facts.count
    return facts[i]
}

struct FactEntry: TimelineEntry {
    let date: Date
    let fact: StreetFact
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> FactEntry {
        FactEntry(date: Date(), fact: allFacts().first ?? fallbackFact)
    }

    func getSnapshot(in context: Context, completion: @escaping (FactEntry) -> Void) {
        completion(FactEntry(date: Date(), fact: factForDay(Date())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FactEntry>) -> Void) {
        // One entry per day for the next week; WidgetKit rolls to the next at
        // each day boundary and asks again when it runs out.
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        var entries: [FactEntry] = []
        for offset in 0..<7 {
            if let day = cal.date(byAdding: .day, value: offset, to: start) {
                entries.append(FactEntry(date: day, fact: factForDay(day)))
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

private let cream = Color(red: 0.957, green: 0.945, blue: 0.902)  // #F4F1E6
private let ink   = Color(red: 0.137, green: 0.125, blue: 0.106)  // #23201B
private let green = Color(red: 0.133, green: 0.318, blue: 0.235)  // #22513C

struct StreetLoreWidgetView: View {
    var entry: FactEntry
    @Environment(\.widgetFamily) private var family

    private var isSmall: Bool { family == .systemSmall }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "signpost.right.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("HISTORY BENEATH YOUR FEET")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(green)

            Text(entry.fact.street)
                .font(.system(size: isSmall ? 17 : 21, weight: .bold, design: .serif))
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(entry.fact.fact)
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
        .configurationDisplayName("Street of the Day")
        .description("A new NYC street name story every day.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct StreetLoreWidgetBundle: WidgetBundle {
    var body: some Widget {
        StreetLoreWidget()
    }
}
