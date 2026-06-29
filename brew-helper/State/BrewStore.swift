import Foundation
import Observation

@Observable
@MainActor
final class BrewStore {
    var installedItems: [BrewItem] = []
    var searchResults: [BrewItem] = []
    var popularItems: [BrewPopularItem] = []
    var services: [BrewService] = []
    var selectedNavigationItem: BrewNavigationItem? = .formulae
    var searchText: String = ""
    var exploreSearchText: String = ""
    var exploreKind: BrewItemKind = .formula
    var explorePeriod: BrewAnalyticsPeriod = .thirtyDays
    var isLoading = false
    var isExploreLoading = false
    var loadingServiceIDs: Set<BrewService.ID> = []
    var message: String?

    private let client: BrewClient

    init(client: BrewClient? = nil) {
        do {
            self.client = try client ?? BrewClient()
        } catch {
            self.client = BrewClient(executor: MissingBrewExecutor(error: error))
            self.message = error.localizedDescription
        }
    }

    var filteredInstalledItems: [BrewItem] {
        installedItems.filter { item in
            let matchesKind = selectedNavigationItem?.itemKind.map { $0 == item.kind } ?? true
            let matchesSearch = searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText)
            return matchesKind && matchesSearch
        }
    }

    var groupedCounts: [(kind: BrewItemKind, count: Int)] {
        BrewItemKind.allCases.map { kind in
            (kind, installedItems.filter { $0.kind == kind }.count)
        }
    }

    var filteredPopularItems: [BrewPopularItem] {
        popularItems.filter { item in
            item.kind == exploreKind
                && item.period == explorePeriod
                && (exploreSearchText.isEmpty || item.name.localizedCaseInsensitiveContains(exploreSearchText))
        }
    }

    func refreshAll() async {
        await loadInstalledItems()
        await loadServices()
    }

    func loadInstalledItems() async {
        await performLoading {
            installedItems = try await client.installedItems()
        }
    }

    func runSearch() async {
        await performLoading {
            searchResults = try await client.search(query: searchText)
        }
    }

    func loadPopularItems() async {
        isExploreLoading = true
        defer { isExploreLoading = false }

        do {
            popularItems = try await client.popularItems(kind: exploreKind, period: explorePeriod)
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    func install(_ item: BrewItem) async {
        await performLoading {
            try await client.install(item)
            searchResults.removeAll { $0.id == item.id }
            installedItems = try await client.installedItems()
        }
    }

    func uninstall(_ item: BrewItem) async {
        await performLoading {
            try await client.uninstall(item)
            installedItems.removeAll { $0.id == item.id }
            services = try await client.services()
        }
    }

    func loadServices() async {
        await performLoading {
            services = try await client.services()
        }
    }

    func start(_ service: BrewService) async {
        await performServiceLoading(service) {
            try await client.startService(named: service.name)
            services = try await client.services()
        }
    }

    func stop(_ service: BrewService) async {
        await performServiceLoading(service) {
            try await client.stopService(named: service.name)
            services = try await client.services()
        }
    }

    func isServiceLoading(_ service: BrewService) -> Bool {
        loadingServiceIDs.contains(service.id)
    }

    func info(for item: BrewItem) async throws -> BrewInfo {
        try await client.info(for: item)
    }

    func info(for service: BrewService) async throws -> BrewInfo {
        try await client.info(for: service)
    }

    private func performLoading(_ operation: () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await operation()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func performServiceLoading(_ service: BrewService, operation: () async throws -> Void) async {
        loadingServiceIDs.insert(service.id)
        defer { loadingServiceIDs.remove(service.id) }

        do {
            try await operation()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct MissingBrewExecutor: BrewCommandExecuting {
    let error: Error

    func run(_ arguments: [String]) async throws -> BrewCommandResult {
        throw error
    }
}
