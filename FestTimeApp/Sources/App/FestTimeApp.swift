import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

#if canImport(GoogleMobileAds)
@MainActor
final class AppOpenAdManager: NSObject, FullScreenContentDelegate {
    static let shared = AppOpenAdManager()

    #if DEBUG
    // Google-provided App Open test unit for simulator/dev verification.
    private let appOpenAdUnitID = "ca-app-pub-3940256099942544/5575463023"
    #else
    private let appOpenAdUnitID = "ca-app-pub-5696830624450387/8235516537"
    #endif
    private var appOpenAd: AppOpenAd?
    private var isLoadingAd = false
    private var isShowingAd = false
    private var adLoadDate: Date?
    private var isAppActive = false

    private override init() {}

    func configure() {
        MobileAds.shared.start(completionHandler: nil)
        loadAdIfNeeded()
    }

    func handleAppDidBecomeActive() {
        isAppActive = true
        showAdIfAvailable()
    }

    func handleAppWillResignActive() {
        isAppActive = false
    }

    private var isAdAvailable: Bool {
        guard let adLoadDate else { return false }
        let isFresh = Date().timeIntervalSince(adLoadDate) < 4 * 60 * 60
        return appOpenAd != nil && isFresh
    }

    private func loadAdIfNeeded() {
        guard !isLoadingAd, !isAdAvailable else { return }

        isLoadingAd = true
        AppOpenAd.load(with: appOpenAdUnitID, request: Request()) { [weak self] ad, error in
            guard let self else { return }
            self.isLoadingAd = false

            if error != nil {
                return
            }

            self.appOpenAd = ad
            self.adLoadDate = Date()

            // On cold start the ad often finishes loading after activation.
            // Try presenting immediately once loaded if app is active.
            if self.isAppActive {
                self.showAdIfAvailable()
            }
        }
    }

    private func showAdIfAvailable(retryAttempt: Int = 0) {
        guard !isShowingAd else { return }

        guard isAdAvailable,
              let appOpenAd else {
            loadAdIfNeeded()
            return
        }

        guard let rootViewController = Self.rootViewController else {
            retryShowIfNeeded(from: retryAttempt)
            return
        }

        isShowingAd = true
        appOpenAd.fullScreenContentDelegate = self
        appOpenAd.present(from: rootViewController)
    }

    private func retryShowIfNeeded(from attempt: Int) {
        guard isAppActive, attempt < 8 else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.showAdIfAvailable(retryAttempt: attempt + 1)
        }
    }

    private static var rootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }

    func adWillDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        isShowingAd = false
        appOpenAd = nil
        adLoadDate = nil
        loadAdIfNeeded()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        isShowingAd = false
        appOpenAd = nil
        adLoadDate = nil
        loadAdIfNeeded()
    }
}
#endif

final class NotificationDelegateProxy: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
#if canImport(GoogleMobileAds)
        AppOpenAdManager.shared.configure()
#endif
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }
}

@main
struct FestTimeApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegateProxy.self) var notificationDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ScheduleView()
                .onAppear {
#if canImport(GoogleMobileAds)
                    AppOpenAdManager.shared.handleAppDidBecomeActive()
#endif
                }
        }
        .onChange(of: scenePhase) { newPhase in
#if canImport(GoogleMobileAds)
            switch newPhase {
            case .active:
                AppOpenAdManager.shared.handleAppDidBecomeActive()
            case .background, .inactive:
                AppOpenAdManager.shared.handleAppWillResignActive()
            @unknown default:
                break
            }
#endif
        }
    }
}
