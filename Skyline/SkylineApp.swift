import SwiftUI

@main
struct SkylineApp: App {
    @State private var model = AppModel()

    init() {
        FontLoader.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
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
