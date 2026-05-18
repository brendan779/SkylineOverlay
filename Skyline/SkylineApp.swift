import SwiftUI

@main
struct SkylineApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(
                    minWidth: Theme.minWindowSize.width,
                    minHeight: Theme.minWindowSize.height
                )
                .preferredColorScheme(.dark)
        }
        .defaultSize(
            width: Theme.defaultWindowSize.width,
            height: Theme.defaultWindowSize.height
        )
        .windowStyle(.hiddenTitleBar)
    }
}
