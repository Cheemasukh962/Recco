import SwiftUI

@main
struct ReccoApp: App {
    /// The one shared model for the whole app. Public builds do not hard-code a
    /// backend deployment URL; provide one with `RECCO_API_BASE_URL`.
    @State private var appModel = AppModel(
        demoMode: ReccoApp.initialDemoMode(),
        apiBaseURL: ReccoApp.apiBaseURL()
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .preferredColorScheme(.dark)
                .task { await appModel.bootstrap() }
        }
    }

    // MARK: - Environment configuration

    private static func initialDemoMode() -> DemoMode {
        if let raw = ProcessInfo.processInfo.environment["DEMO_MODE"],
           let mode = DemoMode(rawValue: raw) {
            return mode
        }
        return .live
    }

    /// Backend base URL. Prefers `RECCO_API_BASE_URL` (HTTP Actions origin),
    /// then `CONVEX_URL`. If neither is set, the app runs in local fallback mode.
    private static func apiBaseURL() -> URL? {
        let env = ProcessInfo.processInfo.environment
        let candidates = [env["RECCO_API_BASE_URL"], env["CONVEX_URL"]]
        for case let raw? in candidates {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, let url = URL(string: trimmed) { return url }
        }
        return nil
    }
}
