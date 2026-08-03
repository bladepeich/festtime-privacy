import Foundation

struct FestivalCatalog: Codable {
    let festivals: [FestivalDefinition]
}

struct FestivalDefinition: Codable, Identifiable, Hashable {
    let id: String
    let legacyIDs: [String]?
    let name: String
    let year: Int
    let days: [FestivalDay]
    let defaultDayID: String
    let defaultShift: Shift
    let forcedShiftByDay: [String: Shift]
    let favoriteIDAliases: [String: String]?
    let menuOptions: [FestivalMenuOption]?
    let eventsFile: String
    let stageColorsFile: String

    var displayName: String {
        "\(name) \(year)"
    }

    var dayNameMap: [String: String] {
        Dictionary(uniqueKeysWithValues: days.map { ($0.id, $0.displayName) })
    }
}

struct FestivalMenuOption: Codable, Hashable, Identifiable {
    let title: String
    let url: String?
    let inAppImageURL: String?
    let systemImage: String?

    var id: String { title }
}

struct FestivalDay: Codable, Hashable {
    let id: String
    let displayName: String
    let calendarDate: String?
}

enum Shift: String, Codable, CaseIterable {
    case dia
    case noche

    var title: String {
        switch self {
        case .dia:
            return "Dia"
        case .noche:
            return "Noche"
        }
    }
}
