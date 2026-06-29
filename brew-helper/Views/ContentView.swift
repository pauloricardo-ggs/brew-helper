import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: BrewStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            DetailView(store: store)
        }
        .accessibilityIdentifier("brewHelperRoot")
        .navigationTitle("Brew Helper")
        .toolbar {
            ToolbarItemGroup {
                RefreshToolbarControl(isLoading: store.isLoading) {
                    Task { await store.refreshAll() }
                }
            }
        }
        .task {
            await store.refreshAll()
        }
    }
}

private struct SidebarView: View {
    @Bindable var store: BrewStore
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("hideDockIcon") private var hideDockIcon = false

    var body: some View {
        List(selection: $store.selectedNavigationItem) {
            SidebarNavigationRow(
                title: BrewNavigationItem.search.title,
                systemImage: BrewNavigationItem.search.systemImage,
                iconColor: color(for: .search),
                count: nil
            )
                .accessibilityIdentifier("sidebar.search")
                .tag(BrewNavigationItem.search)

            Section("Library") {
                ForEach(libraryItems) { item in
                    SidebarNavigationRow(
                        title: item.title,
                        systemImage: item.systemImage,
                        iconColor: color(for: item),
                        count: count(for: item)
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("sidebar.\(item.id.lowercased())")
                    .tag(item)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        .safeAreaInset(edge: .bottom) {
            SidebarSettingsMenu(
                showMenuBarExtra: $showMenuBarExtra,
                hideDockIcon: hideDockBinding
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var libraryItems: [BrewNavigationItem] {
        [.formulae, .casks, .services, .taps]
    }

    private func count(for item: BrewNavigationItem) -> Int? {
        if item == .services {
            return store.services.count
        }

        if let kind = item.itemKind {
            return store.installedItems.filter { $0.kind == kind }.count
        }

        return nil
    }

    private func color(for item: BrewNavigationItem) -> Color {
        switch item {
        case .formulae:
            BrewItemKind.formula.accentColor
        case .casks:
            BrewItemKind.cask.accentColor
        case .taps:
            BrewItemKind.tap.accentColor
        case .services:
            Color(red: 0.34, green: 0.58, blue: 0.66)
        case .search:
            Color(red: 0.58, green: 0.58, blue: 0.66)
        }
    }

    private var hideDockBinding: Binding<Bool> {
        Binding {
            hideDockIcon
        } set: { newValue in
            hideDockIcon = newValue
            if newValue {
                showMenuBarExtra = true
            }
        }
    }
}

private struct SidebarSettingsMenu: View {
    @Binding var showMenuBarExtra: Bool
    @Binding var hideDockIcon: Bool

    var body: some View {
        Menu {
            Toggle("Show in Menu Bar", isOn: $showMenuBarExtra)

            Toggle("Hide Dock Icon", isOn: $hideDockIcon)

            Divider()

            Text("Hiding the Dock keeps Brew Helper available from the menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .frame(width: 22)
                Text("Settings")
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sidebar.settings")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

private struct SidebarNavigationRow: View {
    let title: String
    let systemImage: String
    let iconColor: Color
    let count: Int?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
                .frame(width: 22)

            Text(title)
                .foregroundStyle(.primary)

            Spacer()

            if let count {
                Text(count, format: .number)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DetailView: View {
    @Bindable var store: BrewStore

    var body: some View {
        Group {
            switch store.selectedNavigationItem ?? .formulae {
            case .search:
                SearchInstallView(store: store)
            case .formulae, .casks, .taps:
                InstalledItemsView(store: store)
            case .services:
                ServicesView(store: store)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = store.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }
}

private struct InstalledItemsView: View {
    @Bindable var store: BrewStore
    @State private var pendingRemovalItem: BrewItem?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(store.filteredInstalledItems) { item in
                    BrewItemRow(item: item) {
                        try await store.info(for: item)
                    } action: {
                        pendingRemovalItem = item
                    }
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle(store.selectedNavigationItem?.title ?? "Formulae")
        .searchable(text: $store.searchText, prompt: "Filter installed items")
        .accessibilityIdentifier("installedView")
        .confirmationDialog(
            "Confirm Removal",
            isPresented: Binding(
                get: { pendingRemovalItem != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingRemovalItem = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingRemovalItem
        ) { item in
            Button(removalActionTitle(for: item), role: .destructive) {
                Task { await store.uninstall(item) }
            }

            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(removalMessage(for: item))
        }
    }

    private func removalActionTitle(for item: BrewItem) -> String {
        item.kind == .tap ? "Remove Tap" : "Uninstall"
    }

    private func removalMessage(for item: BrewItem) -> String {
        switch item.kind {
        case .formula:
            "Uninstall formula \(item.name)?"
        case .cask:
            "Uninstall cask \(item.name)? This will use force zap cleanup."
        case .tap:
            "Remove tap \(item.name)?"
        }
    }
}

private struct SearchInstallView: View {
    @Bindable var store: BrewStore

    var body: some View {
        VStack(spacing: 0) {
            BrewSearchBar(store: store)
            .padding()

            Divider()

            List {
                ForEach(store.searchResults) { item in
                    BrewItemRow(item: item) {
                        try await store.info(for: item)
                    } action: {
                        Task { await store.install(item) }
                    }
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("Search")
        .accessibilityIdentifier("searchView")
    }
}

private struct BrewSearchBar: View {
    @Bindable var store: BrewStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            TextField("Formula or cask name", text: $store.searchText)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("searchField")
                .onSubmit {
                    Task { await store.runSearch() }
                }

            if store.searchText.isEmpty == false {
                Button {
                    store.searchText = ""
                    store.searchResults = []
                } label: {
                    Label("Clear", systemImage: "xmark.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear search")
            }

            Divider()
                .frame(height: 20)

            Button {
                Task { await store.runSearch() }
            } label: {
                Label("Search", systemImage: "arrow.right")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityIdentifier("searchButton")
            .help("Search")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ServicesView: View {
    @Bindable var store: BrewStore

    var body: some View {
        List {
            ForEach(store.services) { service in
                BrewServiceRow(service: service, isLoading: store.isServiceLoading(service)) {
                    try await store.info(for: service)
                } startAction: {
                    Task { await store.start(service) }
                } stopAction: {
                    Task { await store.stop(service) }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Services")
        .accessibilityIdentifier("servicesView")
    }
}

private struct RefreshToolbarControl: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: action) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .frame(width: 36, height: 36)
    }
}

private struct InfoButton: View {
    let title: String
    let infoAction: () async throws -> BrewInfo

    @State private var isPresented = false
    @State private var state = BrewInfoPopoverState.idle

    var body: some View {
        Button {
            isPresented = true
            loadInfo()
        } label: {
            Label("Info", systemImage: "info.circle")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .frame(width: 30, height: 30)
        .help("Show info")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            BrewInfoPopover(title: title, state: state)
        }
    }

    private func loadInfo() {
        state = .loading

        Task {
            do {
                state = .loaded(try await infoAction())
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

private enum BrewInfoPopoverState {
    case idle
    case loading
    case loaded(BrewInfo)
    case failed(String)
}

private struct BrewInfoPopover: View {
    let title: String
    let state: BrewInfoPopoverState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch state {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading \(title)...")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 320, height: 80)
            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Could not load info", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(width: 340, alignment: .leading)
            case .loaded(let info):
                BrewInfoContent(info: info)
            }
        }
        .padding(16)
        .frame(width: 420, height: 440, alignment: .topLeading)
    }
}

private struct BrewInfoContent: View {
    let info: BrewInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(info.title)
                    .font(.headline)

                if let subtitle = info.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(info.sections.enumerated()), id: \.offset) { _, section in
                        BrewInfoSectionView(section: section)
                    }
                }
                .padding(.trailing, 6)
                .frame(width: 380, alignment: .leading)
            }
        }
    }
}

private struct BrewInfoSectionView: View {
    let section: BrewInfoSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    BrewInfoValueView(value: row.value)
                }
            }
        }
    }
}

private struct BrewInfoValueView: View {
    let value: String

    var body: some View {
        if let url = singleURL {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Text(value)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .buttonStyle(.link)
                .font(.callout)
        } else {
            Text(value)
                .font(value.contains("\n") ? .system(.caption, design: .monospaced) : .callout)
                .lineLimit(value.contains("\n") ? 12 : 4)
                .truncationMode(.tail)
        }
    }

    private var singleURL: URL? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            trimmedValue.contains(" ") == false,
            let url = URL(string: trimmedValue),
            ["http", "https"].contains(url.scheme?.lowercased())
        else {
            return nil
        }

        return url
    }
}

private struct BrewItemRow: View {
    let item: BrewItem
    let infoAction: () async throws -> BrewInfo
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(item.kind.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.body)
                    BrewKindTag(kind: item.kind)
                }
            }

            Spacer()

            InfoButton(title: item.name, infoAction: infoAction)

            Button {
                action()
            } label: {
                Label(actionTitle, systemImage: actionImage)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("brewItem.\(item.name)")
    }

    private var actionTitle: String {
        if item.installed && item.kind == .tap {
            "Remove"
        } else if item.installed {
            "Uninstall"
        } else {
            "Install"
        }
    }

    private var actionImage: String {
        if item.installed && item.kind == .tap {
            "minus.circle"
        } else if item.installed {
            "trash"
        } else {
            "plus.circle"
        }
    }
}

private struct BrewKindTag: View {
    let kind: BrewItemKind

    var body: some View {
        Text(kind.title)
            .font(.caption)
            .foregroundStyle(kind.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(kind.tintColor, in: Capsule())
    }
}

private struct BrewServiceRow: View {
    let service: BrewService
    let isLoading: Bool
    let infoAction: () async throws -> BrewInfo
    let startAction: () -> Void
    let stopAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: service.status.systemImage)
                .foregroundStyle(statusStyle)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                HStack(spacing: 8) {
                    Text(service.status.title)
                    if let user = service.user {
                        Text(user)
                    }
                    if let file = service.file {
                        Text(file)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            InfoButton(title: service.name, infoAction: infoAction)

            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        if service.status == .started {
                            stopAction()
                        } else {
                            startAction()
                        }
                    } label: {
                        Label(service.status == .started ? "Stop" : "Start", systemImage: service.status == .started ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(width: 86, height: 30)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("brewService.\(service.name)")
    }

    private var statusStyle: Color {
        switch service.status {
        case .started:
            Color(red: 0.38, green: 0.62, blue: 0.46)
        case .stopped:
            Color(red: 1, green: 0.5, blue: 0.5)
        case .unknown:
            Color(red: 0.72, green: 0.55, blue: 0.30)
        }
    }
}

private extension BrewItemKind {
    var accentColor: Color {
        switch self {
        case .formula:
            Color(red: 0.35, green: 0.50, blue: 0.80)
        case .cask:
            Color(red: 0.55, green: 0.42, blue: 0.70)
        case .tap:
            Color(red: 0.38, green: 0.58, blue: 0.48)
        }
    }

    var tintColor: Color {
        switch self {
        case .formula:
            Color(red: 0.35, green: 0.50, blue: 0.80).opacity(0.16)
        case .cask:
            Color(red: 0.55, green: 0.42, blue: 0.70).opacity(0.16)
        case .tap:
            Color(red: 0.38, green: 0.58, blue: 0.48).opacity(0.16)
        }
    }
}

#Preview {
    ContentView(store: BrewStore(client: BrewClient(executor: PreviewBrewExecutor())))
}

private struct PreviewBrewExecutor: BrewCommandExecuting {
    func run(_ arguments: [String]) async throws -> BrewCommandResult {
        let output: String
        switch arguments {
        case ["services", "list"]:
            output = """
            Name    Status  User File
            postgresql@16 started paulo ~/Library/LaunchAgents/homebrew.mxcl.postgresql@16.plist
            redis stopped - -
            """
        case ["list", "--formula"]:
            output = "git\nswiftlint\npostgresql@16\n"
        case ["list", "--cask"]:
            output = "visual-studio-code\n"
        case ["tap"]:
            output = "homebrew/core\nhomebrew/cask\n"
        default:
            output = ""
        }
        return BrewCommandResult(standardOutput: output, standardError: "", exitCode: 0)
    }
}
