import Foundation

struct BrewCommandResult: Sendable {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32
}

protocol BrewCommandExecuting: Sendable {
    func run(_ arguments: [String]) async throws -> BrewCommandResult
}

enum BrewClientError: LocalizedError, Equatable {
    case executableNotFound
    case commandFailed(command: String, message: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Homebrew was not found at /opt/homebrew/bin/brew or /usr/local/bin/brew."
        case let .commandFailed(command, message):
            "\(command) failed: \(message)"
        }
    }
}

struct ProcessBrewExecutor: BrewCommandExecuting {
    let executableURL: URL

    init(fileManager: FileManager = .default) throws {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew"
        ]

        guard let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            throw BrewClientError.executableNotFound
        }

        self.executableURL = URL(fileURLWithPath: path)
    }

    func run(_ arguments: [String]) async throws -> BrewCommandResult {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            return try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finishedProcess in
                    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                    continuation.resume(
                        returning: BrewCommandResult(
                            standardOutput: output,
                            standardError: error,
                            exitCode: finishedProcess.terminationStatus
                        )
                    )
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }.value
    }
}

struct BrewClient: Sendable {
    private let executor: BrewCommandExecuting

    init(executor: BrewCommandExecuting) {
        self.executor = executor
    }

    init() throws {
        self.executor = try ProcessBrewExecutor()
    }

    func installedItems() async throws -> [BrewItem] {
        async let formulae = listedItems(arguments: ["list", "--formula"], kind: .formula)
        async let casks = listedItems(arguments: ["list", "--cask"], kind: .cask)
        async let taps = listedItems(arguments: ["tap"], kind: .tap)

        return try await (formulae + casks + taps).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func search(query: String) async throws -> [BrewItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else { return [] }

        async let formulae = searchItems(arguments: ["search", "--formula", trimmedQuery], kind: .formula)
        async let casks = searchItems(arguments: ["search", "--cask", trimmedQuery], kind: .cask)

        return try await (formulae + casks).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func install(_ item: BrewItem) async throws {
        let arguments = item.kind == .cask ? ["install", "--cask", item.name] : ["install", item.name]
        try await checkedRun(arguments)
    }

    func uninstall(_ item: BrewItem) async throws {
        if item.kind == .tap {
            try await checkedRun(["untap", item.name])
        } else if item.kind == .cask {
            try await uninstallCask(named: item.name)
        } else {
            try await checkedRun(["uninstall", item.name])
            try await checkedRun(["cleanup", item.name])
        }
    }

    func services() async throws -> [BrewService] {
        let result = try await checkedRun(["services", "list"])
        return BrewOutputParser.parseServices(result.standardOutput)
    }

    func startService(named name: String) async throws {
        try await checkedRun(["services", "start", name])
    }

    func stopService(named name: String) async throws {
        try await checkedRun(["services", "stop", name])
    }

    func serviceInfo(named name: String) async throws -> String {
        try await checkedRun(["services", "info", name]).standardOutput
    }

    private func listedItems(arguments: [String], kind: BrewItemKind) async throws -> [BrewItem] {
        let result = try await checkedRun(arguments)
        return BrewOutputParser.parseLineList(result.standardOutput).map { BrewItem(name: $0, kind: kind) }
    }

    private func searchItems(arguments: [String], kind: BrewItemKind) async throws -> [BrewItem] {
        let result = try await checkedRun(arguments)
        return BrewOutputParser.parseLineList(result.standardOutput).map { BrewItem(name: $0, kind: kind, installed: false) }
    }

    private func uninstallCask(named name: String) async throws {
        do {
            try await checkedRun(["uninstall", "--force", "--zap", "--cask", name])
        } catch BrewClientError.commandFailed(_, let message) where message.requiresInteractiveSudo {
            try await checkedRun(["uninstall", "--force", "--cask", name])
        }
    }

    @discardableResult
    private func checkedRun(_ arguments: [String]) async throws -> BrewCommandResult {
        let result = try await executor.run(arguments)
        guard result.exitCode == 0 else {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw BrewClientError.commandFailed(command: "brew \(arguments.joined(separator: " "))", message: message.isEmpty ? fallback : message)
        }
        return result
    }
}

private extension String {
    var requiresInteractiveSudo: Bool {
        localizedCaseInsensitiveContains("a terminal is required to read the password")
            || localizedCaseInsensitiveContains("a password is required")
            || localizedCaseInsensitiveContains("configure an askpass helper")
    }
}

enum BrewOutputParser {
    static func parseLineList(_ output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    static func parseServices(_ output: String) -> [BrewService] {
        output
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap { line -> BrewService? in
                let columns = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
                guard columns.isEmpty == false else { return nil }

                let name = columns[0]
                let status = columns.indices.contains(1) ? parseServiceStatus(columns[1]) : .unknown
                let user = columns.indices.contains(2) && columns[2] != "-" ? columns[2] : nil
                let file = columns.indices.contains(3) && columns[3] != "-" ? columns[3] : nil

                return BrewService(name: name, status: status, user: user, file: file)
            }
    }

    private static func parseServiceStatus(_ value: String) -> BrewServiceStatus {
        switch value.lowercased() {
        case "started":
            .started
        case "stopped", "none":
            .stopped
        default:
            .unknown
        }
    }
}
