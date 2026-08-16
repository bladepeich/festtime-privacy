import CryptoKit
import Foundation

struct RemoteFestivalSyncSummary {
    let fetchedFromNetwork: Bool
    let skippedBecauseNotConfigured: Bool
    let insertedCount: Int
    let updatedCount: Int
    let deletedCount: Int
    let skippedInvalidCount: Int
    let errorMessage: String?

    var appliedChangesCount: Int {
        insertedCount + updatedCount + deletedCount
    }
}

protocol RemoteFestivalFeedSyncing {
    func syncIfNeeded(force: Bool) async -> RemoteFestivalSyncSummary
}

struct RemoteFestivalFeedConfiguration {
    static let userDefaultsURLKey = "festtime.remoteFeedURL"

    // Public default feed URL used when no custom URL is configured in UserDefaults.
    static let fallbackURLString = "https://raw.githubusercontent.com/bladepeich/festtime-privacy/main/appstore/remote-festivals-feed.json"

    static func resolvedURL(defaults: UserDefaults = .standard) -> URL? {
        if let custom = defaults.string(forKey: userDefaultsURLKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty,
           let customURL = URL(string: custom) {
            return customURL
        }

        let fallback = fallbackURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallback.isEmpty else { return nil }
        return URL(string: fallback)
    }
}

final class RemoteFestivalCacheStorage {
    static let shared = RemoteFestivalCacheStorage()

    private let lock = NSLock()
    private let fileManager: FileManager
    private var cachedSnapshot: RemoteFestivalCacheSnapshot?

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadSnapshot() -> RemoteFestivalCacheSnapshot {
        lock.lock()
        defer { lock.unlock() }

        if let cachedSnapshot {
            return cachedSnapshot
        }

        guard let data = try? Data(contentsOf: cacheFileURL),
              let snapshot = try? JSONDecoder().decode(RemoteFestivalCacheSnapshot.self, from: data) else {
            let empty = RemoteFestivalCacheSnapshot(lastAppliedSequence: 0, festivals: [])
            cachedSnapshot = empty
            return empty
        }

        cachedSnapshot = snapshot
        return snapshot
    }

    func saveSnapshot(_ snapshot: RemoteFestivalCacheSnapshot) {
        lock.lock()
        defer { lock.unlock() }

        cachedSnapshot = snapshot

        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        do {
            try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
            try data.write(to: cacheFileURL, options: .atomic)
        } catch {
            // Keep app functional even if cache persistence fails.
        }
    }

    func remoteFestivals() -> [FestivalDefinition] {
        loadSnapshot().festivals.map(\.festival)
    }

    func remoteEvents(for festivalID: String) -> [FestivalEvent]? {
        loadSnapshot().festivals.first(where: { $0.id == festivalID })?.events
    }

    func remoteStageColors(for festivalID: String) -> [String: String]? {
        loadSnapshot().festivals.first(where: { $0.id == festivalID })?.stageColors
    }

    private var cacheDirectoryURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("FestTime", isDirectory: true)
    }

    private var cacheFileURL: URL {
        cacheDirectoryURL.appendingPathComponent("remote-festival-cache.json")
    }
}

struct RemoteFestivalCacheSnapshot: Codable {
    var lastAppliedSequence: Int
    var festivals: [StoredRemoteFestival]
}

struct StoredRemoteFestival: Codable {
    let id: String
    let revision: String
    let festival: FestivalDefinition
    let stageColors: [String: String]
    let events: [FestivalEvent]
}

actor RemoteFestivalFeedService: RemoteFestivalFeedSyncing {
    private let session: URLSession
    private let defaults: UserDefaults
    private let cacheStorage: RemoteFestivalCacheStorage

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        cacheStorage: RemoteFestivalCacheStorage = .shared
    ) {
        self.session = session
        self.defaults = defaults
        self.cacheStorage = cacheStorage
    }

    func syncIfNeeded(force: Bool) async -> RemoteFestivalSyncSummary {
        guard let baseURL = RemoteFestivalFeedConfiguration.resolvedURL(defaults: defaults) else {
            return RemoteFestivalSyncSummary(
                fetchedFromNetwork: false,
                skippedBecauseNotConfigured: true,
                insertedCount: 0,
                updatedCount: 0,
                deletedCount: 0,
                skippedInvalidCount: 0,
                errorMessage: nil
            )
        }

        let resolvedURL = await resolveGitHubRawURLToCommitIfNeeded(baseURL)
        let requestURL = cacheBustedURL(from: resolvedURL)
        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let etagKey = etagStorageKey(for: baseURL)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return RemoteFestivalSyncSummary(
                fetchedFromNetwork: false,
                skippedBecauseNotConfigured: false,
                insertedCount: 0,
                updatedCount: 0,
                deletedCount: 0,
                skippedInvalidCount: 0,
                errorMessage: "No se pudo descargar la actualizacion remota."
            )
        }

        guard let http = response as? HTTPURLResponse else {
            return RemoteFestivalSyncSummary(
                fetchedFromNetwork: true,
                skippedBecauseNotConfigured: false,
                insertedCount: 0,
                updatedCount: 0,
                deletedCount: 0,
                skippedInvalidCount: 0,
                errorMessage: "Respuesta remota invalida."
            )
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            return RemoteFestivalSyncSummary(
                fetchedFromNetwork: true,
                skippedBecauseNotConfigured: false,
                insertedCount: 0,
                updatedCount: 0,
                deletedCount: 0,
                skippedInvalidCount: 0,
                errorMessage: "El servidor remoto respondio con error \(http.statusCode)."
            )
        }

        if let etag = http.value(forHTTPHeaderField: "ETag"), !etag.isEmpty {
            defaults.set(etag, forKey: etagKey)
        }

        let decoder = JSONDecoder()
        let feed: RemoteFestivalsFeedDocument

        do {
            feed = try decoder.decode(RemoteFestivalsFeedDocument.self, from: data)
        } catch {
            return RemoteFestivalSyncSummary(
                fetchedFromNetwork: true,
                skippedBecauseNotConfigured: false,
                insertedCount: 0,
                updatedCount: 0,
                deletedCount: 0,
                skippedInvalidCount: 0,
                errorMessage: "El JSON remoto no tiene un formato valido."
            )
        }

        var snapshot = cacheStorage.loadSnapshot()
        var map = Dictionary(uniqueKeysWithValues: snapshot.festivals.map { ($0.id, $0) })

        var insertedCount = 0
        var updatedCount = 0
        var deletedCount = 0
        var skippedInvalidCount = 0

        if let changes = feed.changes, !changes.isEmpty {
            let sortedChanges = changes.sorted { $0.sequence < $1.sequence }
            var highestAppliedSequence = snapshot.lastAppliedSequence

            for change in sortedChanges where change.sequence > snapshot.lastAppliedSequence {
                switch change.operation {
                case .delete:
                    guard let targetID = change.targetFestivalID else {
                        skippedInvalidCount += 1
                        continue
                    }

                    if map.removeValue(forKey: targetID) != nil {
                        deletedCount += 1
                    }
                    highestAppliedSequence = max(highestAppliedSequence, change.sequence)

                case .upsert:
                    guard let bundle = change.bundle,
                          validate(bundle: bundle) else {
                        skippedInvalidCount += 1
                        continue
                    }

                    let revision = resolvedRevision(
                        explicitRevision: change.revision ?? bundle.revision,
                        bundle: bundle
                    )
                    let record = StoredRemoteFestival(
                        id: bundle.festival.id,
                        revision: revision,
                        festival: bundle.festival,
                        stageColors: bundle.stageColors,
                        events: bundle.events
                    )

                    if let existing = map[bundle.festival.id] {
                        if hasRecordChanged(existing, comparedTo: record) {
                            map[bundle.festival.id] = record
                            updatedCount += 1
                        }
                    } else {
                        map[bundle.festival.id] = record
                        insertedCount += 1
                    }

                    highestAppliedSequence = max(highestAppliedSequence, change.sequence)
                }
            }

            snapshot.lastAppliedSequence = highestAppliedSequence
        } else if let bundles = feed.festivals, !bundles.isEmpty {
            let fullReplace = feed.fullReplace ?? true
            var incomingMap: [String: StoredRemoteFestival] = [:]

            for bundle in bundles {
                guard validate(bundle: bundle) else {
                    skippedInvalidCount += 1
                    continue
                }

                let revision = resolvedRevision(explicitRevision: bundle.revision, bundle: bundle)
                let record = StoredRemoteFestival(
                    id: bundle.festival.id,
                    revision: revision,
                    festival: bundle.festival,
                    stageColors: bundle.stageColors,
                    events: bundle.events
                )
                incomingMap[bundle.festival.id] = record
            }

            if fullReplace {
                let previousIDs = Set(map.keys)
                let incomingIDs = Set(incomingMap.keys)

                let insertedIDs = incomingIDs.subtracting(previousIDs)
                let deletedIDs = previousIDs.subtracting(incomingIDs)
                let commonIDs = previousIDs.intersection(incomingIDs)

                let updatedInCommon = commonIDs.reduce(into: 0) { partialResult, id in
                    guard let previous = map[id],
                          let incoming = incomingMap[id] else {
                        return
                    }
                    if hasRecordChanged(previous, comparedTo: incoming) {
                        partialResult += 1
                    }
                }

                insertedCount += insertedIDs.count
                updatedCount += updatedInCommon
                deletedCount += deletedIDs.count
                map = incomingMap

                // Snapshot mode does not depend on sequence cursor.
                snapshot.lastAppliedSequence = max(snapshot.lastAppliedSequence, feed.maxSequenceHint ?? snapshot.lastAppliedSequence)
            } else {
                for (id, record) in incomingMap {
                    if let existing = map[id] {
                        if hasRecordChanged(existing, comparedTo: record) {
                            map[id] = record
                            updatedCount += 1
                        }
                    } else {
                        map[id] = record
                        insertedCount += 1
                    }
                }
            }
        } else {
            return RemoteFestivalSyncSummary(
                fetchedFromNetwork: true,
                skippedBecauseNotConfigured: false,
                insertedCount: 0,
                updatedCount: 0,
                deletedCount: 0,
                skippedInvalidCount: 0,
                errorMessage: "El feed remoto no contiene festivales ni cambios."
            )
        }

        snapshot.festivals = map.values.sorted { lhs, rhs in
            lhs.festival.displayName.localizedCaseInsensitiveCompare(rhs.festival.displayName) == .orderedAscending
        }

        cacheStorage.saveSnapshot(snapshot)

        return RemoteFestivalSyncSummary(
            fetchedFromNetwork: true,
            skippedBecauseNotConfigured: false,
            insertedCount: insertedCount,
            updatedCount: updatedCount,
            deletedCount: deletedCount,
            skippedInvalidCount: skippedInvalidCount,
            errorMessage: nil
        )
    }

    private func etagStorageKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let suffix = digest.map { String(format: "%02x", $0) }.joined()
        return "festtime.remoteFeedETag.\(suffix)"
    }

    private func cacheBustedURL(from baseURL: URL) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return baseURL
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll(where: { $0.name == "ft_sync_ts" })
        queryItems.append(URLQueryItem(name: "ft_sync_ts", value: String(Int(Date().timeIntervalSince1970))))
        components.queryItems = queryItems

        return components.url ?? baseURL
    }

    private func resolveGitHubRawURLToCommitIfNeeded(_ url: URL) async -> URL {
        guard url.host?.lowercased() == "raw.githubusercontent.com" else {
            return url
        }

        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 4 else {
            return url
        }

        let owner = parts[0]
        let repo = parts[1]
        let branch = parts[2]
        let filePath = parts.dropFirst(3).joined(separator: "/")

        guard !owner.isEmpty, !repo.isEmpty, !branch.isEmpty, !filePath.isEmpty else {
            return url
        }

        guard var components = URLComponents(string: "https://api.github.com/repos/\(owner)/\(repo)/commits/\(branch)") else {
            return url
        }
        components.queryItems = [URLQueryItem(name: "per_page", value: "1")]
        guard let apiURL = components.url else {
            return url
        }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200 ..< 300).contains(http.statusCode),
                  let payload = try? JSONDecoder().decode(GitHubCommitPayload.self, from: data),
                  !payload.sha.isEmpty,
                  let commitURL = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(payload.sha)/\(filePath)") else {
                return url
            }
            return commitURL
        } catch {
            return url
        }
    }

    private func validate(bundle: RemoteFestivalBundleDocument) -> Bool {
        let dayIDs = Set(bundle.festival.days.map(\.id))
        guard !dayIDs.isEmpty else { return false }

        let uniqueEventIDs = Set(bundle.events.map(\.id))
        guard uniqueEventIDs.count == bundle.events.count else { return false }

        for event in bundle.events where !dayIDs.contains(event.dia) {
            return false
        }

        return true
    }

    private func resolvedRevision(explicitRevision: String?, bundle: RemoteFestivalBundleDocument) -> String {
        if let explicitRevision,
           !explicitRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitRevision
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(bundle) else {
            return UUID().uuidString
        }

        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func hasRecordChanged(_ existing: StoredRemoteFestival, comparedTo incoming: StoredRemoteFestival) -> Bool {
        existing.revision != incoming.revision
            || existing.festival != incoming.festival
            || existing.stageColors != incoming.stageColors
            || existing.events != incoming.events
    }
}

private struct GitHubCommitPayload: Decodable {
    let sha: String
}

private struct RemoteFestivalsFeedDocument: Decodable {
    let formatVersion: Int?
    let fullReplace: Bool?
    let maxSequenceHint: Int?
    let festivals: [RemoteFestivalBundleDocument]?
    let changes: [RemoteFestivalChangeDocument]?
}

private struct RemoteFestivalBundleDocument: Codable {
    let revision: String?
    let festival: FestivalDefinition
    let stageColors: [String: String]
    let events: [FestivalEvent]
}

private struct RemoteFestivalChangeDocument: Decodable {
    enum Operation {
        case upsert
        case delete
    }

    let sequence: Int
    let operation: Operation
    let targetFestivalID: String?
    let revision: String?
    let bundle: RemoteFestivalBundleDocument?

    enum CodingKeys: String, CodingKey {
        case sequence
        case op
        case operation
        case festivalID
        case revision
        case bundle
        case festival
        case stageColors
        case events
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        sequence = try container.decode(Int.self, forKey: .sequence)

        let rawOperation = (try? container.decode(String.self, forKey: .operation))
            ?? (try? container.decode(String.self, forKey: .op))
            ?? "upsert"

        switch rawOperation.lowercased() {
        case "delete", "remove":
            operation = .delete
        default:
            operation = .upsert
        }

        revision = try container.decodeIfPresent(String.self, forKey: .revision)
        targetFestivalID = try container.decodeIfPresent(String.self, forKey: .festivalID)

        if let decodedBundle = try container.decodeIfPresent(RemoteFestivalBundleDocument.self, forKey: .bundle) {
            bundle = decodedBundle
        } else if let festival = try container.decodeIfPresent(FestivalDefinition.self, forKey: .festival),
                  let stageColors = try container.decodeIfPresent([String: String].self, forKey: .stageColors),
                  let events = try container.decodeIfPresent([FestivalEvent].self, forKey: .events) {
            bundle = RemoteFestivalBundleDocument(revision: revision, festival: festival, stageColors: stageColors, events: events)
        } else {
            bundle = nil
        }
    }
}
