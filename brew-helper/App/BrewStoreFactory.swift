import Foundation

extension BrewStore {
    static func makeForAppLaunch(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> BrewStore {
        #if DEBUG
        if environment["BREW_HELPER_UI_TESTING"] == "1" {
            return makeUITestingStore()
        }
        #endif

        return BrewStore()
    }
}
