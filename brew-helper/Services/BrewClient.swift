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

    func info(for item: BrewItem) async throws -> BrewInfo {
        switch item.kind {
        case .formula:
            do {
                let result = try await checkedRun(["info", "--json=v2", "--formula", item.name])
                return BrewInfoParser.parseFormulaInfo(result.standardOutput, fallbackName: item.name)
            } catch {
                return try await textInfo(for: item, arguments: ["info", "--formula", item.name])
            }
        case .cask:
            do {
                let result = try await checkedRun(["info", "--json=v2", "--cask", item.name])
                return BrewInfoParser.parseCaskInfo(result.standardOutput, fallbackName: item.name)
            } catch {
                return try await textInfo(for: item, arguments: ["info", "--cask", item.name])
            }
        case .tap:
            return try await tapInfo(named: item.name)
        }
    }

    func info(for service: BrewService) async throws -> BrewInfo {
        let output = try await serviceInfo(named: service.name)
        var rows = [
            BrewInfoRow(label: "Status", value: service.status.title)
        ]

        if let user = service.user {
            rows.append(BrewInfoRow(label: "User", value: user))
        }

        if let file = service.file {
            rows.append(BrewInfoRow(label: "File", value: file))
        }

        var sections = [
            BrewInfoSection(title: "Service", rows: rows)
        ]

        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOutput.isEmpty == false {
            sections.append(
                BrewInfoSection(
                    title: "brew services info",
                    rows: [BrewInfoRow(label: "Output", value: trimmedOutput)]
                )
            )
        }

        return BrewInfo(title: service.name, subtitle: "Homebrew service", sections: sections)
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

    private func tapInfo(named name: String) async throws -> BrewInfo {
        do {
            let result = try await checkedRun(["tap-info", "--json", name])
            return BrewInfoParser.parseTapInfo(result.standardOutput, fallbackName: name)
        } catch {
            let result = try await checkedRun(["tap-info", name])
            return BrewInfo(
                title: name,
                subtitle: "Homebrew tap",
                sections: [
                    BrewInfoSection(
                        title: "tap-info",
                        rows: [BrewInfoRow(label: "Output", value: result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines))]
                    )
                ]
            )
        }
    }

    private func textInfo(for item: BrewItem, arguments: [String]) async throws -> BrewInfo {
        let result = try await checkedRun(arguments)
        return BrewInfoParser.parseTextInfo(
            result.standardOutput,
            title: item.name,
            subtitle: item.kind.infoTitle
        )
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

private enum BrewInfoParser {
    static func parseFormulaInfo(_ output: String, fallbackName: String) -> BrewInfo {
        guard let object = jsonObjects(from: output, rootKey: "formulae").first else {
            return rawInfo(title: fallbackName, subtitle: "Formula", output: output)
        }

        let title = stringValue(object["full_name"]) ?? stringValue(object["name"]) ?? fallbackName
        var rows: [BrewInfoRow] = []
        append("Description", object["desc"], to: &rows)
        append("Homepage", object["homepage"], to: &rows)

        if let versions = object["versions"] as? [String: Any] {
            append("Stable", versions["stable"], to: &rows)
            append("HEAD", versions["head"], to: &rows)
        }

        append("Installed", installedVersions(from: object["installed"]), to: &rows)
        append("Dependencies", object["dependencies"], to: &rows)
        append("Build Dependencies", object["build_dependencies"], to: &rows)
        append("Caveats", object["caveats"], to: &rows)

        return BrewInfo(
            title: title,
            subtitle: "Formula",
            sections: [BrewInfoSection(title: "Details", rows: rows)]
        )
    }

    static func parseCaskInfo(_ output: String, fallbackName: String) -> BrewInfo {
        guard let object = jsonObjects(from: output, rootKey: "casks").first else {
            return rawInfo(title: fallbackName, subtitle: "Cask", output: output)
        }

        let title = stringValue(object["name"]) ?? stringValue(object["token"]) ?? fallbackName
        var rows: [BrewInfoRow] = []
        append("Token", object["token"], to: &rows)
        append("Description", object["desc"], to: &rows)
        append("Homepage", object["homepage"], to: &rows)
        append("Version", object["version"], to: &rows)
        append("Installed", object["installed"], to: &rows)
        append("Artifacts", artifactSummary(from: object["artifacts"]), to: &rows)
        append("Caveats", object["caveats"], to: &rows)

        return BrewInfo(
            title: title,
            subtitle: "Cask",
            sections: [BrewInfoSection(title: "Details", rows: rows)]
        )
    }

    static func parseTapInfo(_ output: String, fallbackName: String) -> BrewInfo {
        guard let object = jsonObjects(from: output).first else {
            return rawInfo(title: fallbackName, subtitle: "Tap", output: output)
        }

        let title = stringValue(object["name"]) ?? fallbackName
        var rows: [BrewInfoRow] = []
        append("Remote", object["remote"], to: &rows)
        append("Path", object["path"], to: &rows)
        append("Branch", object["branch"], to: &rows)
        append("Installed", object["installed"], to: &rows)
        append("Official", object["official"], to: &rows)
        append("Formulae", object["formula_names"], to: &rows)
        append("Casks", object["cask_tokens"], to: &rows)

        return BrewInfo(
            title: title,
            subtitle: "Tap",
            sections: [BrewInfoSection(title: "Details", rows: rows)]
        )
    }

    static func parseTextInfo(_ output: String, title: String, subtitle: String) -> BrewInfo {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return BrewInfo(
            title: title,
            subtitle: subtitle,
            sections: [
                BrewInfoSection(
                    title: "brew info",
                    rows: [
                        BrewInfoRow(
                            label: "Output",
                            value: trimmedOutput.isEmpty ? "No details returned." : trimmedOutput
                        )
                    ]
                )
            ]
        )
    }

    private static func jsonObjects(from output: String, rootKey: String? = nil) -> [[String: Any]] {
        let output = jsonSubstring(from: output) ?? output
        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data)
        else {
            return []
        }

        if let rootKey, let dictionary = json as? [String: Any] {
            return dictionary[rootKey] as? [[String: Any]] ?? []
        }

        if let array = json as? [[String: Any]] {
            return array
        }

        if let dictionary = json as? [String: Any] {
            return [dictionary]
        }

        return []
    }

    private static func append(_ label: String, _ value: Any?, to rows: inout [BrewInfoRow]) {
        guard let value = stringValue(value), value.isEmpty == false else { return }
        rows.append(BrewInfoRow(label: label, value: value))
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return number.stringValue
        case let strings as [String]:
            let compacted = strings.filter { $0.isEmpty == false }
            return compacted.isEmpty ? nil : compacted.joined(separator: ", ")
        case let values as [Any]:
            let compacted = values.compactMap { stringValue($0) }.filter { $0.isEmpty == false }
            return compacted.isEmpty ? nil : compacted.joined(separator: ", ")
        default:
            return nil
        }
    }

    private static func installedVersions(from value: Any?) -> String? {
        guard let installations = value as? [[String: Any]] else {
            return stringValue(value)
        }

        let versions = installations.compactMap { installation in
            stringValue(installation["version"])
        }

        return versions.isEmpty ? nil : versions.joined(separator: ", ")
    }

    private static func artifactSummary(from value: Any?) -> String? {
        guard let artifacts = value as? [[String: Any]] else {
            return stringValue(value)
        }

        let summaries = artifacts.flatMap { artifact in
            artifact.keys.sorted()
        }

        return summaries.isEmpty ? nil : summaries.joined(separator: ", ")
    }

    private static func rawInfo(title: String, subtitle: String, output: String) -> BrewInfo {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return BrewInfo(
            title: title,
            subtitle: subtitle,
            sections: [
                BrewInfoSection(
                    title: "Output",
                    rows: [BrewInfoRow(label: "Details", value: trimmedOutput.isEmpty ? "No details returned." : trimmedOutput)]
                )
            ]
        )
    }

    private static func jsonSubstring(from output: String) -> String? {
        guard
            let start = output.firstIndex(where: { $0 == "{" || $0 == "[" }),
            let end = output.lastIndex(where: { $0 == "}" || $0 == "]" }),
            start <= end
        else {
            return nil
        }

        return String(output[start...end])
    }
}

private extension BrewItemKind {
    var infoTitle: String {
        switch self {
        case .formula:
            "Formula"
        case .cask:
            "Cask"
        case .tap:
            "Tap"
        }
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
