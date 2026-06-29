#if DEBUG
import Foundation

extension BrewStore {
    static func makeUITestingStore() -> BrewStore {
        let store = BrewStore(client: BrewClient(executor: UITestBrewExecutor()))
        store.installedItems = [
            BrewItem(name: "git", kind: .formula),
            BrewItem(name: "swiftlint", kind: .formula),
            BrewItem(name: "postgresql@16", kind: .formula),
            BrewItem(name: "visual-studio-code", kind: .cask),
            BrewItem(name: "homebrew/core", kind: .tap),
            BrewItem(name: "homebrew/cask", kind: .tap)
        ]
        store.searchResults = [
            BrewItem(name: "git", kind: .formula, installed: false),
            BrewItem(name: "git-lfs", kind: .formula, installed: false),
            BrewItem(name: "github", kind: .cask, installed: false)
        ]
        store.popularItems = [
            BrewPopularItem(name: "node", kind: .formula, count: 120_000, period: .thirtyDays),
            BrewPopularItem(name: "python@3.13", kind: .formula, count: 98_000, period: .thirtyDays),
            BrewPopularItem(name: "visual-studio-code", kind: .cask, count: 82_000, period: .thirtyDays),
            BrewPopularItem(name: "iterm2", kind: .cask, count: 65_000, period: .thirtyDays)
        ]
        store.services = [
            BrewService(
                name: "postgresql@16",
                status: .started,
                user: "paulo",
                file: "~/Library/LaunchAgents/homebrew.mxcl.postgresql@16.plist"
            ),
            BrewService(name: "redis", status: .stopped)
        ]
        return store
    }
}

private struct UITestBrewExecutor: BrewCommandExecuting {
    func run(_ arguments: [String]) async throws -> BrewCommandResult {
        let output: String

        switch arguments {
        case ["list", "--formula"]:
            output = "git\nswiftlint\npostgresql@16\n"
        case ["list", "--cask"]:
            output = "visual-studio-code\n"
        case ["tap"]:
            output = "homebrew/core\nhomebrew/cask\n"
        case ["services", "list"]:
            output = """
            Name Status User File
            postgresql@16 started paulo ~/Library/LaunchAgents/homebrew.mxcl.postgresql@16.plist
            redis stopped - -
            """
        case let search where search.starts(with: ["search", "--formula"]):
            output = "git\ngit-lfs\n"
        case let search where search.starts(with: ["search", "--cask"]):
            output = "github\n"
        default:
            output = ""
        }

        return BrewCommandResult(standardOutput: output, standardError: "", exitCode: 0)
    }
}

private extension Array where Element == String {
    func starts(with prefix: [String]) -> Bool {
        count >= prefix.count && Array(self[0..<prefix.count]) == prefix
    }
}
#endif
