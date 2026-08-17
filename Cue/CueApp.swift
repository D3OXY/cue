import SwiftUI

@main
struct CueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The sheet is an NSPanel owned by AppDelegate; no SwiftUI windows.
        Settings { EmptyView() }
    }
}
