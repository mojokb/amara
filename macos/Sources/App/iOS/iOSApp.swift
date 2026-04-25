import SwiftUI
import AmaraKit

@main
struct Amara_iOSApp: App {
    @StateObject private var ghostty_app: Amara.App

    init() {
        if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
            preconditionFailure("Initialize ghostty backend failed")
        }
        _ghostty_app = StateObject(wrappedValue: Amara.App())
    }

    var body: some Scene {
        WindowGroup {
            iOS_AmaraTerminal()
                .environmentObject(ghostty_app)
        }
    }
}

struct iOS_AmaraTerminal: View {
    @EnvironmentObject private var ghostty_app: Amara.App

    var body: some View {
        ZStack {
            // Make sure that our background color extends to all parts of the screen
            Color(ghostty_app.config.backgroundColor).ignoresSafeArea()

            Amara.Terminal()
        }
    }
}

struct iOS_AmaraInitView: View {
    @EnvironmentObject private var ghostty_app: Amara.App

    var body: some View {
        VStack {
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 96)
            Text("Amara")
            Text("State: \(ghostty_app.readiness.rawValue)")
        }
        .padding()
    }
}
