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

enum BrewAnalyticsPeriod: String, CaseIterable, Identifiable, Codable, Sendable {
    case thirtyDays = "30d"
    case ninetyDays = "90d"
    case year = "365d"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thirtyDays:
            "30 days"
        case .ninetyDays:
            "90 days"
        case .year:
            "365 days"
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

struct BrewPopularItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let kind: BrewItemKind
    let count: Int
    let period: BrewAnalyticsPeriod

    init(name: String, kind: BrewItemKind, count: Int, period: BrewAnalyticsPeriod) {
        self.name = name
        self.kind = kind
        self.count = count
        self.period = period
        self.id = "\(kind.rawValue):\(period.rawValue):\(name)"
    }

    var brewItem: BrewItem {
        BrewItem(name: name, kind: kind, installed: false)
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

struct BrewInfo: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let sections: [BrewInfoSection]
}

struct BrewInfoSection: Equatable, Sendable {
    let title: String
    let rows: [BrewInfoRow]
}

struct BrewInfoRow: Equatable, Sendable {
    let label: String
    let value: String
}

enum BrewNavigationItem: Hashable, Identifiable {
    case search
    case explore
    case formulae
    case casks
    case services
    case taps

    var id: String { title }

    var title: String {
        switch self {
        case .search:
            "Search"
        case .explore:
            "Explore"
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
        case .explore:
            "chart.bar.xaxis"
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
        case .search, .explore, .services:
            nil
        }
    }
}
