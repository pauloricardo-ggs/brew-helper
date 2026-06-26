import Testing
@testable import brew_helper

struct BrewHelperTests {
    @Test func parsesLineListsIgnoringBlankLines() {
        let items = BrewOutputParser.parseLineList("git\n\n swiftlint \n")

        #expect(items == ["git", "swiftlint"])
    }

    @Test func parsesHomebrewServicesList() {
        let output = """
        Name          Status  User  File
        postgresql@16 started paulo ~/Library/LaunchAgents/homebrew.mxcl.postgresql@16.plist
        redis         stopped -     -
        mysql         error   paulo ~/Library/LaunchAgents/homebrew.mxcl.mysql.plist
        """

        let services = BrewOutputParser.parseServices(output)

        #expect(services.count == 3)
        #expect(services[0].name == "postgresql@16")
        #expect(services[0].status == .started)
        #expect(services[0].user == "paulo")
        #expect(services[1].status == .stopped)
        #expect(services[1].user == nil)
        #expect(services[2].status == .unknown)
    }

    @Test @MainActor func loadsInstalledFormulaeCasksAndTaps() async throws {
        let executor = RecordingBrewExecutor(outputs: [
            ["list", "--formula"]: "git\nswiftlint\n",
            ["list", "--cask"]: "visual-studio-code\n",
            ["tap"]: "homebrew/core\nhomebrew/cask\n"
        ])
        let client = BrewClient(executor: executor)

        let items = try await client.installedItems()

        #expect(items.map(\.name).sorted() == ["git", "homebrew/cask", "homebrew/core", "swiftlint", "visual-studio-code"])
        #expect(items.filter { $0.kind == .formula }.count == 2)
        #expect(items.filter { $0.kind == .cask }.count == 1)
        #expect(items.filter { $0.kind == .tap }.count == 2)
    }

    @Test @MainActor func searchesFormulaeAndCasks() async throws {
        let executor = RecordingBrewExecutor(outputs: [
            ["search", "--formula", "git"]: "git\ngit-lfs\n",
            ["search", "--cask", "git"]: "github\n"
        ])
        let client = BrewClient(executor: executor)

        let results = try await client.search(query: "git")

        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.installed == false })
        #expect(results.contains(BrewItem(name: "github", kind: .cask, installed: false)))
    }

    @Test @MainActor func uninstallUsesExpectedCommandForEachInstalledKind() async throws {
        let executor = RecordingBrewExecutor(outputs: [
            ["uninstall", "git"]: "",
            ["cleanup", "git"]: "",
            ["uninstall", "--force", "--zap", "--cask", "github"]: "",
            ["untap", "qdrant/tap"]: ""
        ])
        let client = BrewClient(executor: executor)

        try await client.uninstall(BrewItem(name: "git", kind: .formula))
        try await client.uninstall(BrewItem(name: "github", kind: .cask))
        try await client.uninstall(BrewItem(name: "qdrant/tap", kind: .tap))

        let commands = await executor.commands
        #expect(commands.contains(["uninstall", "git"]))
        #expect(commands.contains(["cleanup", "git"]))
        #expect(commands.contains(["uninstall", "--force", "--zap", "--cask", "github"]))
        #expect(commands.contains(["untap", "qdrant/tap"]))
    }

    @Test @MainActor func caskUninstallFallsBackWhenZapRequiresSudoPassword() async throws {
        let sudoError = """
        sudo: a terminal is required to read the password; either use the -S option to read from standard input or configure an askpass helper
        sudo: a password is required
        """
        let executor = RecordingBrewExecutor(
            outputs: [
                ["uninstall", "--force", "--zap", "--cask", "stats"]: "",
                ["uninstall", "--force", "--cask", "stats"]: ""
            ],
            errors: [
                ["uninstall", "--force", "--zap", "--cask", "stats"]: sudoError
            ],
            exitCodes: [
                ["uninstall", "--force", "--zap", "--cask", "stats"]: 1
            ]
        )
        let client = BrewClient(executor: executor)

        try await client.uninstall(BrewItem(name: "stats", kind: .cask))

        let commands = await executor.commands
        #expect(commands == [
            ["uninstall", "--force", "--zap", "--cask", "stats"],
            ["uninstall", "--force", "--cask", "stats"]
        ])
    }

    @Test @MainActor func installUsesExpectedCommandForFormulaeAndCasks() async throws {
        let executor = RecordingBrewExecutor(outputs: [
            ["install", "git"]: "",
            ["install", "--cask", "github"]: ""
        ])
        let client = BrewClient(executor: executor)

        try await client.install(BrewItem(name: "git", kind: .formula, installed: false))
        try await client.install(BrewItem(name: "github", kind: .cask, installed: false))

        let commands = await executor.commands
        #expect(commands.contains(["install", "git"]))
        #expect(commands.contains(["install", "--cask", "github"]))
    }

    @Test @MainActor func serviceCommandsUseExpectedArguments() async throws {
        let executor = RecordingBrewExecutor(outputs: [
            ["services", "start", "redis"]: "",
            ["services", "stop", "redis"]: "",
            ["services", "info", "redis"]: "redis started"
        ])
        let client = BrewClient(executor: executor)

        try await client.startService(named: "redis")
        try await client.stopService(named: "redis")
        let info = try await client.serviceInfo(named: "redis")

        let commands = await executor.commands
        #expect(info == "redis started")
        #expect(commands.contains(["services", "start", "redis"]))
        #expect(commands.contains(["services", "stop", "redis"]))
        #expect(commands.contains(["services", "info", "redis"]))
    }

    @Test @MainActor func commandFailureThrowsBrewClientError() async throws {
        let executor = RecordingBrewExecutor(
            outputs: [["install", "missing"]: "fallback"],
            errors: [["install", "missing"]: "not found"],
            exitCodes: [["install", "missing"]: 1]
        )
        let client = BrewClient(executor: executor)

        await #expect(throws: BrewClientError.commandFailed(command: "brew install missing", message: "not found")) {
            try await client.install(BrewItem(name: "missing", kind: .formula, installed: false))
        }
    }

    @Test @MainActor func storeRefreshesInstalledItemsAndServices() async {
        let executor = RecordingBrewExecutor(outputs: [
            ["list", "--formula"]: "git\n",
            ["list", "--cask"]: "visual-studio-code\n",
            ["tap"]: "homebrew/core\n",
            ["services", "list"]: """
            Name Status User File
            redis stopped - -
            """
        ])
        let store = BrewStore(client: BrewClient(executor: executor))

        await store.refreshAll()

        #expect(store.installedItems.count == 3)
        #expect(store.services == [BrewService(name: "redis", status: .stopped)])
        #expect(store.message == nil)
    }

    @Test @MainActor func storeInstallAndUninstallRefreshInstalledItems() async {
        let executor = RecordingBrewExecutor(outputs: [
            ["install", "git"]: "",
            ["uninstall", "git"]: "",
            ["cleanup", "git"]: "",
            ["list", "--formula"]: "git\n",
            ["list", "--cask"]: "",
            ["tap"]: "",
            ["services", "list"]: "Name Status User File\n"
        ])
        let store = BrewStore(client: BrewClient(executor: executor))
        let item = BrewItem(name: "git", kind: .formula, installed: false)

        await store.install(item)
        #expect(store.installedItems == [BrewItem(name: "git", kind: .formula)])

        await store.uninstall(BrewItem(name: "git", kind: .formula))
        let commands = await executor.commands
        #expect(commands.contains(["install", "git"]))
        #expect(commands.contains(["uninstall", "git"]))
    }

    @Test @MainActor func appLaunchStoreProvidesMenuBarServicesForUITesting() {
        let store = BrewStore.makeForAppLaunch(environment: ["BREW_HELPER_UI_TESTING": "1"])

        #expect(store.services.contains(BrewService(name: "postgresql@16", status: .started, user: "paulo", file: "~/Library/LaunchAgents/homebrew.mxcl.postgresql@16.plist")))
        #expect(store.services.contains(BrewService(name: "redis", status: .stopped)))
    }
}

actor RecordingBrewExecutor: BrewCommandExecuting {
    private(set) var commands: [[String]] = []
    private let outputs: [[String]: String]
    private let errors: [[String]: String]
    private let exitCodes: [[String]: Int32]

    init(
        outputs: [[String]: String],
        errors: [[String]: String] = [:],
        exitCodes: [[String]: Int32] = [:]
    ) {
        self.outputs = outputs
        self.errors = errors
        self.exitCodes = exitCodes
    }

    func run(_ arguments: [String]) async throws -> BrewCommandResult {
        commands.append(arguments)

        return BrewCommandResult(
            standardOutput: outputs[arguments, default: ""],
            standardError: errors[arguments, default: ""],
            exitCode: exitCodes[arguments, default: 0]
        )
    }
}
