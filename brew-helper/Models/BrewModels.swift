import Foundation

enum BrewItemKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case formula
    case cask
    case tap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formula:
            "Formulae"
        case .cask:
            "Casks"
        case .tap:
            "Taps"
        }
    }

    var systemImage: String {
        switch self {
        case .formula:
            "shippingbox"
        case .cask:
            "macwindow"
        case .tap:
            "sink"
        }
    }
}

struct BrewItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let kind: BrewItemKind
    let installed: Bool

    init(name: String, kind: BrewItemKind, installed: Bool = true) {
        self.name = name
        self.kind = kind
        self.installed = installed
        self.id = "\(kind.rawValue):\(name)"
    }
}

enum BrewServiceStatus: String, Codable, Sendable {
    case started
    case stopped
    case unknown

    var title: String {
        switch self {
        case .started:
            "Started"
        case .stopped:
            "Stopped"
        case .unknown:
            "Unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .started:
            "checkmark.circle.fill"
        case .stopped:
            "stop.circle.fill"
        case .unknown:
            "questionmark.circle.fill"
        }
    }
}

struct BrewService: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let status: BrewServiceStatus
    let user: String?
    let file: String?

    init(name: String, status: BrewServiceStatus, user: String? = nil, file: String? = nil) {
        self.name = name
        self.status = status
        self.user = user
        self.file = file
        self.id = name
    }
}

enum BrewNavigationItem: Hashable, Identifiable {
    case search
    case formulae
    case casks
    case services
    case taps

    var id: String { title }

    var title: String {
        switch self {
        case .search:
            "Search"
        case .formulae:
            "Formulae"
        case .casks:
            "Casks"
        case .services:
            "Services"
        case .taps:
            "Taps"
        }
    }

    var systemImage: String {
        switch self {
        case .search:
            "magnifyingglass"
        case .formulae:
            BrewItemKind.formula.systemImage
        case .casks:
            BrewItemKind.cask.systemImage
        case .services:
            "server.rack"
        case .taps:
            BrewItemKind.tap.systemImage
        }
    }

    var itemKind: BrewItemKind? {
        switch self {
        case .formulae:
            .formula
        case .casks:
            .cask
        case .taps:
            .tap
        case .search, .services:
            nil
        }
    }
}
