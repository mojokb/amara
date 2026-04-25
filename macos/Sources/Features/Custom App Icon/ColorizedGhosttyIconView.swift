import SwiftUI
import Cocoa

// For testing.
struct ColorizedAmaraIconView: View {
    var body: some View {
        Image(nsImage: ColorizedAmaraIcon(
            screenColors: [.purple, .blue],
            ghostColor: .yellow,
            frame: .aluminum
        ).makeImage(in: .main)!)
    }
}
