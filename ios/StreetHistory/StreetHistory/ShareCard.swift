import SwiftUI
import UIKit

/// A street-sign styled card rendered to an image for sharing.
struct ShareCard: View {
    let headline: String       // big line, e.g. "42 streets"
    let subhead: String        // e.g. "explored in NYC"
    let footnote: String?      // e.g. "Bay Ridge, Brooklyn — complete"

    private let green = Color(red: 0.0, green: 0.42, blue: 0.30)
    private let cream = Color(red: 0.96, green: 0.93, blue: 0.86)

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Text("N Y C")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(6)
                    .foregroundStyle(cream.opacity(0.85))
                Rectangle().fill(cream.opacity(0.6)).frame(width: 120, height: 2)
                Text(headline)
                    .font(.system(size: 68, weight: .black, design: .rounded))
                    .foregroundStyle(cream)
                    .multilineTextAlignment(.center)
                Text(subhead)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(cream.opacity(0.9))
                if let footnote {
                    Text(footnote)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(cream.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(40)
            Spacer()
            Text("StreetLore")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(cream.opacity(0.75))
                .padding(.bottom, 28)
        }
        .frame(width: 400, height: 500)
        .background(
            ZStack {
                green
                RoundedRectangle(cornerRadius: 0)
                    .stroke(cream.opacity(0.7), lineWidth: 6)
                    .padding(18)
            }
        )
    }

    @MainActor
    func rendered() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        return renderer.uiImage
    }
}
