import Foundation

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var festivals: [FestivalDefinition] = []
    @Published private(set) var eventsByFestival: [String: [FestivalEvent]] = [:]
    @Published private(set) var stageColorsByFestival: [String: [String: String]] = [:]
    @Published private(set) var favoritesByFestival: [String: Set<String>] = [:]

    private var eventsByFestivalDayShift: [String: [String: [Shift: [FestivalEvent]]]] = [:]
    private var eventsByFestivalID: [String: [String: FestivalEvent]] = [:]
    private var festivalLookupByID: [String: FestivalDefinition] = [:]

    @Published var selectedFestivalID: String = ""
    @Published var selectedDayID: String = ""
    @Published var selectedShift: Shift = .noche
    @Published var selectedStage: String = "todos"
    @Published var searchText: String = ""
    @Published var isFavoritesTabActive: Bool = false
    @Published var remindersEnabled: Bool = false
    @Published var reminderErrorMessage: String?
    @Published var festivalChangeMessage: String?
    @Published var isRemoteSyncInProgress: Bool = false
    @Published var remoteSyncDelayMessage: String?
    @Published var isStartupLoading: Bool = false
    @Published var startupProgress: Double = 0.05
    @Published var startupStatusMessage: String = "Preparando app..."
    @Published var lastSuccessfulRemoteSyncDate: Date?
    @Published var notificationInbox: [FestTimeNotificationItem] = []
    @Published var unreadNotificationsCount: Int = 0

    private let repository: FestivalRepository
    private let remoteFeedSyncService: RemoteFestivalFeedSyncing
    private let reminderScheduler: FavoriteReminderScheduling
    private let defaults: UserDefaults
    private let favoritesSecureStore: FavoritesSecureStoring

    private let selectedFestivalKey = "festtime.selectedFestival"
    private let selectedDayPrefix = "festtime.selectedDay."
    private let selectedShiftPrefix = "festtime.selectedShift."
    private let selectedStagePrefix = "festtime.selectedStage."
    private let searchPrefix = "festtime.search."
    private let favoritesPrefix = "festtime.favorites."
    private let firstLoadPrefix = "festtime.firstLoadDone."
    private let remindersEnabledPrefix = "festtime.remindersEnabled."
    private let lastRemoteSyncAtKey = "festtime.lastRemoteSyncAt"
    private let reminderOffsets = [15, 10, 5]
    private var remoteSyncAttemptID = UUID()

    init(
        repository: FestivalRepository = BundleFestivalRepository(),
        remoteFeedSyncService: RemoteFestivalFeedSyncing = RemoteFestivalFeedService(),
        reminderScheduler: FavoriteReminderScheduling = FavoriteReminderScheduler(),
        defaults: UserDefaults = .standard,
        favoritesSecureStore: FavoritesSecureStoring = FavoritesKeychainStore()
    ) {
        self.repository = repository
        self.remoteFeedSyncService = remoteFeedSyncService
        self.reminderScheduler = reminderScheduler
        self.defaults = defaults
        self.favoritesSecureStore = favoritesSecureStore

        if defaults.object(forKey: lastRemoteSyncAtKey) != nil {
            let timestamp = defaults.double(forKey: lastRemoteSyncAtKey)
            lastSuccessfulRemoteSyncDate = Date(timeIntervalSince1970: timestamp)
        }
    }

    var selectedFestival: FestivalDefinition? {
        festivalLookupByID[selectedFestivalID]
    }

    var allEvents: [FestivalEvent] {
        guard !selectedFestivalID.isEmpty else { return [] }
        return eventsByFestival[selectedFestivalID] ?? []
    }

    var stageColors: [String: String] {
        guard !selectedFestivalID.isEmpty else { return [:] }
        return stageColorsByFestival[selectedFestivalID] ?? [:]
    }

    var favorites: Set<String> {
        guard !selectedFestivalID.isEmpty else { return [] }

        if let cached = favoritesByFestival[selectedFestivalID] {
            return cached
        }

        let key = favoriteStorageKey(for: selectedFestivalID)
        let values = readFavorites(forKey: key)
        return Set(values)
    }

    var availableShifts: [Shift] {
        guard let festival = selectedFestival else { return [.dia, .noche] }
        if let forced = festival.forcedShiftByDay[selectedDayID] {
            return [forced]
        }
        return [.dia, .noche]
    }

    var availableStages: [String] {
        let baseEvents: [FestivalEvent]
        if isFavoritesTabActive {
            baseEvents = favoriteEventsForSelectedFestival()
        } else {
            baseEvents = eventsByFestivalDayShift[selectedFestivalID]?[selectedDayID]?[selectedShift] ?? []
        }

        return Array(Set(baseEvents.map(\.escenario))).sorted()
    }

    var filteredScheduleEvents: [FestivalEvent] {
        var events = eventsByFestivalDayShift[selectedFestivalID]?[selectedDayID]?[selectedShift] ?? []
        if events.isEmpty {
            events = allEvents.filter { $0.dia == selectedDayID && $0.turno == selectedShift }
            events.sort(by: byTimeThenArtist)
        }
        events = applySharedFilters(to: events)
        return events
    }

    var groupedFavoriteEvents: [(dayName: String, events: [FestivalEvent])] {
        var events = favoriteEventsForSelectedFestival()
        events = applySharedFilters(to: events)

        guard let festival = selectedFestival else { return [] }

        let groups = Dictionary(grouping: events, by: \.dia)
        return festival.days.compactMap { day in
            guard let items = groups[day.id], !items.isEmpty else { return nil }
            return (day.displayName, items.sorted(by: byTimeThenArtist))
        }
    }

    var festivalsGroupedByMonth: [(title: String, festivals: [FestivalDefinition])] {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.dateFormat = "yyyy-MM-dd"

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "es_ES")
        monthFormatter.calendar = Calendar(identifier: .gregorian)
        monthFormatter.dateFormat = "LLLL yyyy"

        let calendar = Calendar(identifier: .gregorian)
        var buckets: [String: (monthDate: Date, festivals: [FestivalDefinition])] = [:]
        var undated: [FestivalDefinition] = []

        for festival in festivals {
            guard let firstDate = firstFestivalDate(for: festival, parser: parser) else {
                undated.append(festival)
                continue
            }

            let components = calendar.dateComponents([.year, .month], from: firstDate)
            guard let year = components.year,
                  let month = components.month,
                  let monthDate = calendar.date(from: DateComponents(calendar: calendar, year: year, month: month, day: 1)) else {
                undated.append(festival)
                continue
            }

            let key = String(format: "%04d-%02d", year, month)
            if buckets[key] == nil {
                buckets[key] = (monthDate, [])
            }
            buckets[key]?.festivals.append(festival)
        }

        var grouped = buckets.values
            .sorted { $0.monthDate > $1.monthDate }
            .map { bucket in
                let title = monthFormatter.string(from: bucket.monthDate)
                    .capitalized(with: Locale(identifier: "es_ES"))
                let festivals = bucket.festivals.sorted {
                    let lhsDate = firstFestivalDate(for: $0, parser: parser) ?? .distantPast
                    let rhsDate = firstFestivalDate(for: $1, parser: parser) ?? .distantPast

                    if lhsDate == rhsDate {
                        return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }
                    return lhsDate > rhsDate
                }
                return (title, festivals)
            }

        if !undated.isEmpty {
            grouped.append((
                "Sin fecha",
                undated.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            ))
        }

        return grouped
    }

    var lastRemoteSyncLabel: String {
        guard let date = lastSuccessfulRemoteSyncDate else {
            return "Nunca"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    func load() {
        if !festivals.isEmpty {
            return
        }

        do {
            let loadedFestivals = try repository.loadCatalog()

            festivals = loadedFestivals
            rebuildFestivalLookup()

            // App starts with no festival selected; data loads after explicit user choice.
            selectedFestivalID = ""
            selectedDayID = ""
            selectedStage = "todos"
            searchText = ""
            remindersEnabled = false
            isFavoritesTabActive = false
            Task {
                await syncRemoteFestivals(force: false, showNoChangesMessage: false)
                await rescheduleEnabledFestivalsReminders()
                await refreshNotificationInbox()
            }
        } catch {
            print("Error loading festivals: \(error)")
        }
    }

    func refreshFestivalsFromRemote() {
        Task {
            await syncRemoteFestivals(force: true, showNoChangesMessage: true)
        }
    }

    func prepareRemindersForBackground() {
        Task {
            await rescheduleEnabledFestivalsReminders()
            await refreshNotificationInbox()
        }
    }

    func reloadAfterForeground() {
        do {
            let loadedFestivals = try repository.loadCatalog()
            festivals = loadedFestivals
            rebuildFestivalLookup()

            // Keep the welcome screen stable: do not auto-open a saved festival
            // when the current selection is empty.
            guard !selectedFestivalID.isEmpty,
                  let festival = festivals.first(where: { $0.id == selectedFestivalID }) else {
                return
            }

            // Force refresh of festival resources after app resumes.
            eventsByFestival[festival.id] = try repository.loadEvents(for: festival)
            rebuildEventIndexes(for: festival.id)
            stageColorsByFestival[festival.id] = try repository.loadStageColors(for: festival)

            selectedFestivalID = festival.id
            loadFavoritesIfNeeded(for: festival.id)
            applyFestivalDefaultsAndSelections()

            Task {
                await syncRemoteFestivals(force: false, showNoChangesMessage: false)
                await refreshNotificationInbox()
            }
        } catch {
            print("Error refreshing data after foreground: \(error)")
        }
    }

    func selectFestival(_ festivalID: String) {
        guard selectedFestivalID != festivalID else { return }

        guard let festival = festivals.first(where: { $0.id == festivalID }) else {
            return
        }

        do {
            try loadFestivalDataIfNeeded(for: festival)
            loadFavoritesIfNeeded(for: festival.id)
        } catch {
            print("Error loading selected festival data: \(error)")
        }

        selectedFestivalID = festivalID
        defaults.set(festivalID, forKey: selectedFestivalKey)
        applyFestivalDefaultsAndSelections()
        showInfoMessage("Festival cargado: \(festival.displayName)")
    }

    func selectDay(_ dayID: String) {
        selectedDayID = dayID
        persistDay()

        if let forced = selectedFestival?.forcedShiftByDay[dayID] {
            selectedShift = forced
            persistShift()
        }

        resetStage()
    }

    func selectShift(_ shift: Shift) {
        selectedShift = shift
        persistShift()
        resetStage()
    }

    func selectStage(_ stage: String) {
        selectedStage = stage
        persistStage()
    }

    func toggleFavorite(_ eventID: String) {
        var current = favorites
        if current.contains(eventID) {
            current.remove(eventID)
        } else {
            current.insert(eventID)
        }

        persistFavorites(Array(current), forKey: favoriteStorageKey(for: selectedFestivalID))
        favoritesByFestival[selectedFestivalID] = current

        if remindersEnabled {
            Task {
                await rescheduleFavoriteReminders()
            }
        }
    }

    func updateSearch(_ text: String) {
        searchText = text
        let key = searchPrefix + selectedFestivalID
        defaults.set(text, forKey: key)
    }

    func toggleFavoritesTab() {
        isFavoritesTabActive.toggle()
        resetStage()
    }

    func setRemindersEnabled(_ enabled: Bool) {
        if !enabled {
            remindersEnabled = false
            persistRemindersEnabled()
            Task {
                await reminderScheduler.clearReminders(for: selectedFestivalID)
                await refreshNotificationInbox()
            }
            return
        }

        Task {
            let granted = await reminderScheduler.requestAuthorization()
            guard granted else {
                remindersEnabled = false
                persistRemindersEnabled()
                reminderErrorMessage = "Activa las notificaciones en Ajustes para recibir avisos con alarma."
                return
            }

            remindersEnabled = true
            persistRemindersEnabled()
            await rescheduleFavoriteReminders()

            let pendingCount = await reminderScheduler.pendingReminderCount(for: selectedFestivalID)
            if pendingCount == 0 {
                reminderErrorMessage = "Alertas activadas, pero no hay recordatorios futuros. Marca favoritos con hora futura o revisa fecha/hora del dispositivo."
            }

            await refreshNotificationInbox()
        }
    }

    func sendTestNotification() {
        Task {
            let granted = await reminderScheduler.requestAuthorization()
            guard granted else {
                reminderErrorMessage = "No hay permisos de notificaciones. Activalos en Ajustes > Notificaciones > FestTime."
                return
            }

            do {
                try await reminderScheduler.scheduleTestNotification(after: 10)
                reminderErrorMessage = "Aviso de prueba programado para dentro de 10 segundos."
                await refreshNotificationInbox()
            } catch {
                reminderErrorMessage = "No se pudo programar el aviso de prueba."
            }
        }
    }

    func refreshNotificationInbox() async {
        let delivered = await reminderScheduler.deliveredFestTimeNotifications()
        notificationInbox = delivered
        unreadNotificationsCount = delivered.count
        await reminderScheduler.setAppBadgeCount(delivered.count)
    }

    func markNotificationAsRead(_ notificationID: String) {
        Task {
            await reminderScheduler.markDeliveredNotificationsAsRead(ids: [notificationID])
            await refreshNotificationInbox()
        }
    }

    func markAllNotificationsAsRead() {
        Task {
            let ids = notificationInbox.map(\.id)
            await reminderScheduler.markDeliveredNotificationsAsRead(ids: ids)
            await refreshNotificationInbox()
        }
    }

    func clearAllNotifications() {
        Task {
            await reminderScheduler.clearAllFestTimeNotifications()
            await refreshNotificationInbox()
            reminderErrorMessage = "Notificaciones borradas."
        }
    }

    func clearReminderError() {
        reminderErrorMessage = nil
    }

    private func applyFestivalDefaultsAndSelections() {
        guard let festival = selectedFestival else { return }

        let firstLoadKey = firstLoadPrefix + festival.id
        let isFirstLoadForFestival = !defaults.bool(forKey: firstLoadKey)

        let dayKey = selectedDayPrefix + festival.id
        let shiftKey = selectedShiftPrefix + festival.id
        let stageKey = selectedStagePrefix + festival.id
        let searchKey = searchPrefix + festival.id

        if isFirstLoadForFestival {
            selectedDayID = festival.days.first?.id ?? festival.defaultDayID
            if let forced = festival.forcedShiftByDay[selectedDayID] {
                selectedShift = forced
            } else {
                selectedShift = [.dia, .noche].first ?? festival.defaultShift
            }
            selectedStage = "todos"
            searchText = ""
            defaults.set(true, forKey: firstLoadKey)
        } else {
            selectedDayID = defaults.string(forKey: dayKey) ?? festival.defaultDayID
            if !festival.days.contains(where: { $0.id == selectedDayID }) {
                selectedDayID = festival.defaultDayID
            }

            let shiftValue = defaults.string(forKey: shiftKey)
            let storedShift = shiftValue.flatMap(Shift.init(rawValue:)) ?? festival.defaultShift
            if let forced = festival.forcedShiftByDay[selectedDayID] {
                selectedShift = forced
            } else {
                selectedShift = storedShift
            }

            selectedStage = defaults.string(forKey: stageKey) ?? "todos"
            searchText = defaults.string(forKey: searchKey) ?? ""
        }

        if !availableShifts.contains(selectedShift) {
            selectedShift = availableShifts.first ?? festival.defaultShift
        }

        if selectedStage != "todos" && !availableStages.contains(selectedStage) {
            selectedStage = "todos"
        }
        remindersEnabled = defaults.bool(forKey: remindersEnabledPrefix + festival.id)

        // Always enter a festival on the schedule tab, not on favorites-only mode.
        isFavoritesTabActive = false

        migrateFavoritesIfNeeded(for: festival)
        loadFavoritesIfNeeded(for: festival.id)

        defaults.set(festival.id, forKey: selectedFestivalKey)
        persistDay()
        persistShift()
        persistStage()

        if remindersEnabled {
            Task {
                await rescheduleFavoriteReminders()
            }
        }
    }

    private func applySharedFilters(to events: [FestivalEvent]) -> [FestivalEvent] {
        var filtered = events

        if selectedStage != "todos" {
            filtered = filtered.filter { $0.escenario == selectedStage }
        }

        if !searchText.isEmpty {
            let normalized = searchText.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            filtered = filtered.filter { $0.searchArtist.contains(normalized) }
        }

        return filtered
    }

    private func byTimeThenArtist(_ lhs: FestivalEvent, _ rhs: FestivalEvent) -> Bool {
        if lhs.sortableMinutes == rhs.sortableMinutes {
            return lhs.artista.localizedCaseInsensitiveCompare(rhs.artista) == .orderedAscending
        }
        return lhs.sortableMinutes < rhs.sortableMinutes
    }

    private func resetStage() {
        selectedStage = "todos"
        persistStage()
    }

    private func persistDay() {
        let key = selectedDayPrefix + selectedFestivalID
        defaults.set(selectedDayID, forKey: key)
    }

    private func persistShift() {
        let key = selectedShiftPrefix + selectedFestivalID
        defaults.set(selectedShift.rawValue, forKey: key)
    }

    private func persistStage() {
        let key = selectedStagePrefix + selectedFestivalID
        defaults.set(selectedStage, forKey: key)
    }

    private func favoriteStorageKey(for festivalID: String) -> String {
        favoritesPrefix + festivalID
    }

    private func migrateFavoritesIfNeeded(for festival: FestivalDefinition) {
        let currentKey = favoriteStorageKey(for: festival.id)
        let currentStored = readFavorites(forKey: currentKey)
        let hasCurrentFavoritesKey = hasFavoritesValue(forKey: currentKey)
        var currentFavorites = favoritesByFestival[festival.id] ?? Set(currentStored)

        if !hasCurrentFavoritesKey {
            for legacyFestivalID in (festival.legacyIDs ?? []) {
                let legacyKey = favoriteStorageKey(for: legacyFestivalID)
                let legacyFavorites = readFavorites(forKey: legacyKey)
                currentFavorites.formUnion(legacyFavorites)
            }
        }

        if let aliases = festival.favoriteIDAliases, !aliases.isEmpty {
            currentFavorites = Set(currentFavorites.map { aliases[$0] ?? $0 })
        }

        let storedSorted = currentStored.sorted()
        let migratedSorted = Array(currentFavorites).sorted()
        if !hasCurrentFavoritesKey || storedSorted != migratedSorted {
            persistFavorites(Array(currentFavorites), forKey: currentKey)
        }

        favoritesByFestival[festival.id] = currentFavorites
    }

    private func persistRemindersEnabled() {
        let key = remindersEnabledPrefix + selectedFestivalID
        defaults.set(remindersEnabled, forKey: key)
    }

    private func favoriteEventsForSelectedFestival() -> [FestivalEvent] {
        let favoriteIDs = favorites

        if let indexedEvents = eventsByFestivalID[selectedFestivalID], !indexedEvents.isEmpty {
            return favoriteIDs.compactMap { indexedEvents[$0] }
        }

        return allEvents.filter { favoriteIDs.contains($0.id) }
    }

    private func rescheduleFavoriteReminders() async {
        guard remindersEnabled,
              let festival = selectedFestival else {
            return
        }

        do {
            try await reminderScheduler.scheduleReminders(
                festival: festival,
                events: favoriteEventsForSelectedFestival(),
                favoriteIDs: favorites,
                reminderMinutes: reminderOffsets
            )
            if reminderErrorMessage == "No se pudieron programar los avisos con alarma." {
                reminderErrorMessage = nil
            }
        } catch {
            reminderErrorMessage = "No se pudieron programar los avisos con alarma."
        }
    }

    private func loadFestivalDataIfNeeded(for festival: FestivalDefinition) throws {
        if eventsByFestival[festival.id] == nil {
            eventsByFestival[festival.id] = try repository.loadEvents(for: festival)
            rebuildEventIndexes(for: festival.id)
        }

        if stageColorsByFestival[festival.id] == nil {
            stageColorsByFestival[festival.id] = try repository.loadStageColors(for: festival)
        }
    }

    private func loadFavoritesIfNeeded(for festivalID: String) {
        if favoritesByFestival[festivalID] == nil {
            let key = favoriteStorageKey(for: festivalID)
            let values = readFavorites(forKey: key)
            favoritesByFestival[festivalID] = Set(values)
        }
    }

    private func readFavorites(forKey key: String) -> [String] {
        if let secureValues = favoritesSecureStore.loadFavorites(for: key) {
            return secureValues
        }

        let fallback = defaults.array(forKey: key) as? [String] ?? []
        if defaults.object(forKey: key) != nil {
            _ = favoritesSecureStore.saveFavorites(fallback, for: key)
        }

        return fallback
    }

    private func persistFavorites(_ values: [String], forKey key: String) {
        defaults.set(values, forKey: key)
        _ = favoritesSecureStore.saveFavorites(values, for: key)
    }

    private func hasFavoritesValue(forKey key: String) -> Bool {
        if favoritesSecureStore.loadFavorites(for: key) != nil {
            return true
        }

        return defaults.object(forKey: key) != nil
    }

    private func showInfoMessage(_ message: String) {
        festivalChangeMessage = message

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if festivalChangeMessage == message {
                festivalChangeMessage = nil
            }
        }
    }

    private func rescheduleEnabledFestivalsReminders() async {
        guard await reminderScheduler.hasNotificationPermission() else {
            return
        }

        for festival in festivals {
            let remindersKey = remindersEnabledPrefix + festival.id
            guard defaults.bool(forKey: remindersKey) else { continue }

            do {
                try loadFestivalDataIfNeeded(for: festival)
                loadFavoritesIfNeeded(for: festival.id)

                let favoriteIDs = favoritesByFestival[festival.id] ?? []
                let festivalEvents = eventsByFestival[festival.id] ?? []

                try await reminderScheduler.scheduleReminders(
                    festival: festival,
                    events: festivalEvents,
                    favoriteIDs: favoriteIDs,
                    reminderMinutes: reminderOffsets
                )
            } catch {
                print("Error rescheduling reminders for \(festival.id): \(error)")
            }
        }
    }

    private func syncRemoteFestivals(force: Bool, showNoChangesMessage: Bool) async {
        let attemptID = UUID()
        remoteSyncAttemptID = attemptID
        remoteSyncDelayMessage = nil
        isRemoteSyncInProgress = true

        Task { @MainActor [attemptID] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard isRemoteSyncInProgress,
                  remoteSyncAttemptID == attemptID else {
                return
            }
            remoteSyncDelayMessage = "La actualizacion esta tardando mas de lo normal..."
        }

        defer {
            isRemoteSyncInProgress = false
            remoteSyncDelayMessage = nil
        }

        let summary = await remoteFeedSyncService.syncIfNeeded(force: force)

        if let errorMessage = summary.errorMessage {
            if force {
                reminderErrorMessage = errorMessage
            }
            return
        }

        if summary.skippedBecauseNotConfigured {
            if force {
                reminderErrorMessage = "No hay URL remota configurada para actualizar festivales."
            }
            return
        }

        markRemoteSyncSuccess()

        let shouldReloadLocalData = force || summary.appliedChangesCount > 0 || summary.skippedInvalidCount > 0

        guard shouldReloadLocalData else {
            return
        }

        do {
            festivals = try repository.loadCatalog()
            rebuildFestivalLookup()
            pruneLocalCachesToKnownFestivals()

            // Remote changes may affect festivals not currently selected.
            // Clearing these caches ensures next access reads fresh data.
            eventsByFestival.removeAll()
            stageColorsByFestival.removeAll()
            eventsByFestivalDayShift.removeAll()
            eventsByFestivalID.removeAll()

            if let currentFestival = festivals.first(where: { $0.id == selectedFestivalID }) {
                try loadFestivalDataIfNeeded(for: currentFestival)
            } else {
                selectedFestivalID = ""
                selectedDayID = ""
                selectedStage = "todos"
                searchText = ""
                remindersEnabled = false
            }

            let applied = summary.appliedChangesCount
            let skipped = summary.skippedInvalidCount

            if skipped > 0 {
                showInfoMessage("Actualizacion remota: \(applied) cambios, \(skipped) omitidos por validacion")
            } else if applied == 0 {
                if force, showNoChangesMessage {
                    showInfoMessage("Catalogo remoto al dia")
                }
            } else {
                showInfoMessage("Actualizacion remota aplicada: \(applied) cambios")
            }
        } catch {
            if force {
                reminderErrorMessage = "Se recibio una actualizacion remota, pero no se pudo aplicar."
            }
        }
    }

    private func pruneLocalCachesToKnownFestivals() {
        let validIDs = Set(festivals.map(\.id))

        eventsByFestival = eventsByFestival.filter { validIDs.contains($0.key) }
        stageColorsByFestival = stageColorsByFestival.filter { validIDs.contains($0.key) }
        favoritesByFestival = favoritesByFestival.filter { validIDs.contains($0.key) }
        eventsByFestivalDayShift = eventsByFestivalDayShift.filter { validIDs.contains($0.key) }
        eventsByFestivalID = eventsByFestivalID.filter { validIDs.contains($0.key) }
    }

    private func rebuildFestivalLookup() {
        festivalLookupByID = Dictionary(uniqueKeysWithValues: festivals.map { ($0.id, $0) })
    }

    private func rebuildEventIndexes(for festivalID: String) {
        guard let events = eventsByFestival[festivalID] else {
            eventsByFestivalDayShift[festivalID] = nil
            eventsByFestivalID[festivalID] = nil
            return
        }

        var groupedByDayShift: [String: [Shift: [FestivalEvent]]] = [:]
        var eventByID: [String: FestivalEvent] = [:]

        for event in events {
            groupedByDayShift[event.dia, default: [:]][event.turno, default: []].append(event)
            eventByID[event.id] = event
        }

        for dayID in groupedByDayShift.keys {
            guard var shifts = groupedByDayShift[dayID] else {
                continue
            }

            for shift in shifts.keys {
                shifts[shift]?.sort(by: byTimeThenArtist)
            }

            groupedByDayShift[dayID] = shifts
        }

        eventsByFestivalDayShift[festivalID] = groupedByDayShift
        eventsByFestivalID[festivalID] = eventByID
    }

    private func firstFestivalDate(for festival: FestivalDefinition, parser: DateFormatter) -> Date? {
        festival.days
            .compactMap { day -> Date? in
                guard let rawDate = day.calendarDate else { return nil }
                return parser.date(from: rawDate)
            }
            .min()
    }

    private func markRemoteSyncSuccess() {
        let now = Date()
        lastSuccessfulRemoteSyncDate = now
        defaults.set(now.timeIntervalSince1970, forKey: lastRemoteSyncAtKey)
    }
}
