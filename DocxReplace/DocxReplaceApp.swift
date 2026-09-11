import SwiftUI

@main
struct DocxReplaceApp: App {
    @StateObject private var localization = Localization.shared

    var body: some Scene {
        WindowGroup(localization.strings.appTitle) {
            ContentView()
                .frame(minWidth: 760, minHeight: 560)
        }
    }
}
