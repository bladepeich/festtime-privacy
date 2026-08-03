import Foundation

protocol FestivalRepository {
    func loadCatalog() throws -> [FestivalDefinition]
    func loadEvents(for festival: FestivalDefinition) throws -> [FestivalEvent]
    func loadStageColors(for festival: FestivalDefinition) throws -> [String: String]
}

enum FestivalRepositoryError: Error {
    case missingResource(String)
}

struct BundleFestivalRepository: FestivalRepository {
    private let decoder = JSONDecoder()

    func loadCatalog() throws -> [FestivalDefinition] {
        let data = try loadData(named: "festivals", ext: "json")
        return try decoder.decode(FestivalCatalog.self, from: data).festivals
    }

    func loadEvents(for festival: FestivalDefinition) throws -> [FestivalEvent] {
        let data = try loadData(named: festival.eventsFile, ext: "json")
        return try decoder.decode([FestivalEvent].self, from: data)
    }

    func loadStageColors(for festival: FestivalDefinition) throws -> [String: String] {
        let data = try loadData(named: festival.stageColorsFile, ext: "json")
        return try decoder.decode([String: String].self, from: data)
    }

    private func loadData(named name: String, ext: String) throws -> Data {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return try Data(contentsOf: url)
        }

        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Festivals") {
            return try Data(contentsOf: url)
        }

        if let url = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil)?.first(where: {
            $0.deletingPathExtension().lastPathComponent == name
        }) {
            return try Data(contentsOf: url)
        }

        throw FestivalRepositoryError.missingResource("\(name).\(ext)")
    }
}
