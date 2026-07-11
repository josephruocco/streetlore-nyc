import SwiftUI

struct LaunchScreenView: View {
    var body: some View {
        GeometryReader { proxy in
            Image("LaunchImage")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .ignoresSafeArea()
        .background(Color.black)
    }
}
