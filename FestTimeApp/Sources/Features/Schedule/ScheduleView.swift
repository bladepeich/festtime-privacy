import SwiftUI
import UIKit

struct ScheduleView: View {
    @StateObject private var viewModel = ScheduleViewModel()
    @State private var isFestivalSheetPresented = false
    @State private var isNotificationsSheetPresented = false
    @State private var selectedInAppMenuOption: FestivalMenuOption?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.selectedFestival == nil {
                    welcomeView
                } else {
                    festivalContent
                        .searchable(text: Binding(
                            get: { viewModel.searchText },
                            set: { viewModel.updateSearch($0) }
                        ), placement: .automatic, prompt: "Buscar artista")
                }
            }
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if viewModel.isRemoteSyncInProgress {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(.black)
                            Text("Actualizando festivales...")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(.black)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.yellow.opacity(0.92))
                        .clipShape(Capsule(style: .continuous))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let festivalMessage = viewModel.festivalChangeMessage {
                        Text(festivalMessage)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.94))
                            .clipShape(Capsule(style: .continuous))
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 8)
            }
            .toolbar(viewModel.selectedFestival == nil ? .visible : .hidden, for: .navigationBar)
            .scrollDismissesKeyboard(.immediately)
            .alert("Avisos", isPresented: Binding(
                get: { viewModel.reminderErrorMessage != nil },
                set: { if !$0 { viewModel.clearReminderError() } }
            )) {
                Button("OK", role: .cancel) {
                    viewModel.clearReminderError()
                }
            } message: {
                Text(viewModel.reminderErrorMessage ?? "")
            }
            .sheet(isPresented: $isFestivalSheetPresented) {
                festivalSheet
            }
            .sheet(isPresented: $isNotificationsSheetPresented) {
                notificationsSheet
            }
            .sheet(item: $selectedInAppMenuOption) { option in
                menuImageSheet(for: option)
            }
        }
        .overlay {
            if viewModel.isStartupLoading {
                startupLoadingOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isStartupLoading)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRemoteSyncInProgress)
        .task {
            viewModel.load()
            await viewModel.refreshNotificationInbox()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                viewModel.reloadAfterForeground()
            case .background:
                viewModel.prepareRemindersForBackground()
            default:
                break
            }
        }
    }

    private var startupLoadingOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.92), Color(red: 0.08, green: 0.12, blue: 0.19).opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView(value: max(0.0, min(1.0, viewModel.startupProgress)))
                    .progressViewStyle(.linear)
                    .tint(.yellow)
                    .frame(maxWidth: 280)

                Text("Actualizando festivales...")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)

                Text(viewModel.startupStatusMessage)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            .padding(22)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24)
        }
    }

    private var festivalContent: some View {
        VStack(spacing: 0) {
            topControlsBar

            if let festivalMessage = viewModel.festivalChangeMessage {
                Text(festivalMessage)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.yellow.opacity(0.85))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            header
            dayTabs
            shiftTabs
            stageChips
            eventList
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.festivalChangeMessage)
    }

    private var topControlsBar: some View {
        ZStack {
            appLogoCompact
                .frame(maxWidth: .infinity)

            HStack {
                favoritesButton
                Spacer()
                appActionsMenu
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var welcomeView: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.13, blue: 0.20), Color(red: 0.12, green: 0.16, blue: 0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer(minLength: 40)

                VStack(spacing: 18) {
                    appLogoLarge

                    Button {
                        isFestivalSheetPresented = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "music.note.list")
                            Text("Seleccionar festival")
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)

                    Button {
                        viewModel.refreshFestivalsFromRemote()
                    } label: {
                        HStack(spacing: 10) {
                            if viewModel.isRemoteSyncInProgress {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }

                            Text(viewModel.isRemoteSyncInProgress ? "Actualizando..." : "Actualizar festivales")
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .disabled(viewModel.isRemoteSyncInProgress)

                    Text("Ultima actualizacion: \(viewModel.lastRemoteSyncLabel)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .padding(.top, 2)

                    Text("En colaboración con:")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.9))

                    magazineLogoView

                    Link(destination: URL(string: "https://lachicadeayer.news")!) {
                        HStack(spacing: 8) {
                            Image(systemName: "safari")
                            Text("Ir a la revista")
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.94))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 24)

                }

                Spacer()
            }
            .padding(.vertical, 24)
        }
    }

    private var appLogoName: String {
        if UIImage(named: "festtime-logo") != nil { return "festtime-logo" }
        return ""
    }

    private var magazineLogoName: String {
        if colorScheme == .dark {
            if UIImage(named: "lcda-logo-dark") != nil { return "lcda-logo-dark" }
            if UIImage(named: "lcda-logo-light") != nil { return "lcda-logo-light" }
        } else {
            if UIImage(named: "lcda-logo-light") != nil { return "lcda-logo-light" }
            if UIImage(named: "lcda-logo-dark") != nil { return "lcda-logo-dark" }
        }
        return ""
    }

    @ViewBuilder
    private var appLogoLarge: some View {
        if !appLogoName.isEmpty {
            Image(appLogoName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 340)
        } else {
            Text("Añade el logo en festtime-logo.imageset")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var appLogoCompact: some View {
        if !appLogoName.isEmpty {
            Image(appLogoName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 200, maxHeight: 46)
                .accessibilityLabel("FestTime")
        } else {
            Text("FestTime")
                .font(.headline.weight(.bold))
        }
    }

    private var appActionsMenu: some View {
        Menu {
            Button {
                isFestivalSheetPresented = true
            } label: {
                Label("Seleccionar festival", systemImage: "music.note.list")
            }

            Button {
                viewModel.refreshFestivalsFromRemote()
            } label: {
                Label("Actualizar festivales", systemImage: "arrow.clockwise")
            }

            Button {
                viewModel.setRemindersEnabled(!viewModel.remindersEnabled)
            } label: {
                Label(
                    viewModel.remindersEnabled ? "Desactivar alertas" : "Activar alertas",
                    systemImage: viewModel.remindersEnabled ? "bell.slash" : "bell.badge"
                )
            }

            Button {
                isNotificationsSheetPresented = true
            } label: {
                Label("Notificaciones (\(viewModel.unreadNotificationsCount))", systemImage: "tray.full")
            }

            if let selectedFestival = viewModel.selectedFestival,
               let menuOptions = selectedFestival.menuOptions,
               !menuOptions.isEmpty {
                Divider()

                Text(selectedFestival.displayName)

                ForEach(menuOptions) { option in
                    if let imageURLString = option.inAppImageURL,
                       URL(string: imageURLString) != nil {
                        Button {
                            selectedInAppMenuOption = option
                        } label: {
                            Label(option.title, systemImage: option.systemImage ?? "photo")
                        }
                    } else if let urlString = option.url,
                              let url = URL(string: urlString) {
                        Link(destination: url) {
                            Label(option.title, systemImage: option.systemImage ?? "link")
                        }
                    } else {
                        Label(option.title, systemImage: option.systemImage ?? "link")
                    }
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(8)
                    .background(Color.white.opacity(0.94))
                    .clipShape(Circle())

                if viewModel.unreadNotificationsCount > 0 {
                    Text("\(min(viewModel.unreadNotificationsCount, 99))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 8, y: -6)
                }
            }
        }
        .accessibilityLabel("Menu")
    }

    private var notificationsSheet: some View {
        NavigationStack {
            Group {
                if viewModel.notificationInbox.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Sin notificaciones pendientes")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
                    List(viewModel.notificationInbox) { item in
                        Button {
                            viewModel.markNotificationAsRead(item.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text(item.body)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Notificaciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.notificationInbox.isEmpty {
                        Button("Marcar leidas") {
                            viewModel.markAllNotificationsAsRead()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if !viewModel.notificationInbox.isEmpty {
                            Button("Marcar leidas") {
                                viewModel.markAllNotificationsAsRead()
                            }
                        }

                        Button(role: .destructive) {
                            viewModel.clearAllNotifications()
                        } label: {
                            Label("Borrar notificaciones", systemImage: "trash")
                        }

                        Divider()

                        Button("Cerrar") {
                            isNotificationsSheetPresented = false
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            await viewModel.refreshNotificationInbox()
        }
    }

    private var favoritesButton: some View {
        Button {
            viewModel.toggleFavoritesTab()
        } label: {
            Label("Favoritos", systemImage: viewModel.isFavoritesTabActive ? "star.fill" : "star")
                .font(.subheadline.bold())
                .foregroundStyle(.black)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(viewModel.isFavoritesTabActive ? Color.yellow.opacity(0.85) : Color.white.opacity(0.94))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Favoritos")
    }

    @ViewBuilder
    private var magazineLogoView: some View {
        if !magazineLogoName.isEmpty {
            Image(magazineLogoName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            if let selectedFestival = viewModel.selectedFestival {
                Text("Festival seleccionado: \(selectedFestival.displayName)")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .padding(.horizontal)
            }

            Text("Avisos y alarma para favoritos: 15, 10 y 5 min antes")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal)

            Text("Ultima actualizacion: \(viewModel.lastRemoteSyncLabel)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal)
        }
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.90, green: 0.22, blue: 0.27), Color(red: 0.11, green: 0.21, blue: 0.34)], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func menuImageSheet(for option: FestivalMenuOption) -> some View {
        NavigationStack {
            Group {
                if let imageURLString = option.inAppImageURL,
                   let imageURL = URL(string: imageURLString) {
                    ZoomableFestivalImageView(imageURL: imageURL)
                } else {
                    Text("Esta opcion no tiene imagen disponible")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle(option.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        selectedInAppMenuOption = nil
                    }
                }
            }
        }
    }

    private var festivalSheet: some View {
        NavigationStack {
            List {
                ForEach(viewModel.festivalsGroupedByMonth, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.festivals) { festival in
                            Button {
                                let festivalID = festival.id
                                isFestivalSheetPresented = false

                                // Defer loading to the next runloop so the sheet closes immediately.
                                DispatchQueue.main.async {
                                    viewModel.selectFestival(festivalID)
                                }
                            } label: {
                                HStack {
                                    Text(festival.displayName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if festival.id == viewModel.selectedFestivalID {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            .navigationTitle("Festivales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    appLogoCompact
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        isFestivalSheetPresented = false
                    }
                }
            }
        }
    }

    private var dayTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.selectedFestival?.days ?? [], id: \.id) { day in
                    Button(day.displayName) {
                        viewModel.selectDay(day.id)
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.bold())
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .foregroundStyle(.black)
                    .background(viewModel.selectedDayID == day.id ? Color.yellow.opacity(0.85) : Color.white.opacity(0.94))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var shiftTabs: some View {
        if !viewModel.isFavoritesTabActive {
            HStack(spacing: 8) {
                ForEach(viewModel.availableShifts, id: \.self) { shift in
                    Button(shift.title) {
                        viewModel.selectShift(shift)
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.black)
                    .background(viewModel.selectedShift == shift ? Color.yellow.opacity(0.85) : Color.white.opacity(0.94))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }

    private var stageChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                stageChip(title: "Todos", colorHex: "#495057", stageID: "todos")
                ForEach(viewModel.availableStages, id: \.self) { stage in
                    stageChip(title: stage, colorHex: viewModel.stageColors[stage] ?? "#6c757d", stageID: stage)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    private func stageChip(title: String, colorHex: String, stageID: String) -> some View {
        let isSelected = viewModel.selectedStage == stageID

        return Button(title) {
            viewModel.selectStage(stageID)
        }
        .buttonStyle(.plain)
        .font(.caption.bold())
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .foregroundStyle(isSelected ? .white : Color(hex: colorHex))
        .background(isSelected ? Color(hex: colorHex) : Color.clear)
        .overlay(
            Capsule()
                .stroke(Color(hex: colorHex), lineWidth: 1.5)
        )
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var eventList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if viewModel.isFavoritesTabActive {
                    if viewModel.groupedFavoriteEvents.isEmpty {
                        emptyState(icon: "star", title: "Sin favoritos", subtitle: "Marca con estrella los conciertos que no te quieres perder")
                    } else {
                        ForEach(viewModel.groupedFavoriteEvents, id: \.dayName) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                favoriteDayHeader(title: group.dayName)

                                ForEach(group.events) { event in
                                    EventCardView(
                                        event: event,
                                        stageColorHex: viewModel.stageColors[event.escenario] ?? "#6c757d",
                                        isFavorite: viewModel.favorites.contains(event.id),
                                        onToggleFavorite: { viewModel.toggleFavorite(event.id) }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                        }
                    }
                } else {
                    if viewModel.filteredScheduleEvents.isEmpty {
                        emptyState(icon: "magnifyingglass", title: "Sin conciertos", subtitle: "No hay actuaciones para este filtro")
                    } else {
                        ForEach(viewModel.filteredScheduleEvents) { event in
                            EventCardView(
                                event: event,
                                stageColorHex: viewModel.stageColors[event.escenario] ?? "#6c757d",
                                isFavorite: viewModel.favorites.contains(event.id),
                                onToggleFavorite: { viewModel.toggleFavorite(event.id) }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
    }

    private func favoriteDayHeader(title: String) -> some View {
        HStack {
            Image(systemName: "calendar")
                .font(.caption.weight(.bold))
            Text(title)
                .font(.headline.weight(.bold))
        }
        .foregroundStyle(.black)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }
}

private struct ZoomableFestivalImageView: View {
    let imageURL: URL

    @State private var steadyScale: CGFloat = 1.0
    @GestureState private var gestureScale: CGFloat = 1.0

    private var currentScale: CGFloat {
        min(max(steadyScale * gestureScale, 1.0), 5.0)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView("Cargando imagen...")
                            .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    case .success(let image):
                        let fittedWidth = max(proxy.size.width - 24, 1)

                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: fittedWidth)
                            .scaleEffect(currentScale)
                            .frame(
                                width: fittedWidth * currentScale,
                                height: max(proxy.size.height - 24, 1) * currentScale,
                                alignment: .center
                            )
                            .padding(12)
                            .contentShape(Rectangle())
                            .gesture(
                                MagnificationGesture()
                                    .updating($gestureScale) { value, state, _ in
                                        state = value
                                    }
                                    .onEnded { value in
                                        steadyScale = min(max(steadyScale * value, 1.0), 5.0)
                                    }
                            )
                    case .failure:
                        VStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title2)
                            Text("No se pudo cargar la imagen")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) {
                Text("Pellizca para ampliar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
            }
        }
    }
}
