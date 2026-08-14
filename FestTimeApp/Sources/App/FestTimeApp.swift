import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

#if canImport(GoogleMobileAds)
protocol AppOpenAdManagerDelegate: AnyObject {
    /// Called when the app-open ad lifecycle completes (dismissed or failed to present).
    func appOpenAdManagerAdDidComplete(_ appOpenAdManager: AppOpenAdManager)
}

@MainActor
final class AppOpenAdManager: NSObject, FullScreenContentDelegate {
    static let shared = AppOpenAdManager()

    // Google-provided App Open test unit used across builds while testing.
    private let appOpenAdUnitID = "ca-app-pub-3940256099942544/5575463023"
    private var appOpenAd: AppOpenAd?
    weak var appOpenAdManagerDelegate: AppOpenAdManagerDelegate?
    private var isLoadingAd = false
    private var isShowingAd = false
    private var loadTime: Date?
    private let timeoutInterval: TimeInterval = 4 * 3_600
    private var isAppActive = false
    private var hasShownInCurrentForeground = false

    private override init() {}

    func configure() {
        MobileAds.shared.requestConfiguration.testDeviceIdentifiers = ["SIMULATOR"]
        MobileAds.shared.start(completionHandler: nil)
        Task {
            await loadAd()
        }
    }

    func handleAppDidBecomeActive() {
        isAppActive = true

        guard !hasShownInCurrentForeground else { return }
        showAdIfAvailable()
    }

    func handleAppWillResignActive() {
        isAppActive = false
    }

    func handleAppDidEnterBackground() {
        isAppActive = false
        hasShownInCurrentForeground = false
    }

    private func isAdAvailable() -> Bool {
        guard appOpenAd != nil,
              let loadTime else {
            return false
        }

        return Date().timeIntervalSince(loadTime) < timeoutInterval
    }

    func loadAd() async {
        guard !isLoadingAd, !isAdAvailable() else { return }
        isLoadingAd = true
        defer { isLoadingAd = false }

        do {
            let request = Request()
            request.scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first

            appOpenAd = try await AppOpenAd.load(with: appOpenAdUnitID, request: request)
            appOpenAd?.fullScreenContentDelegate = self
            loadTime = Date()

            // On cold start, ad load can finish after activation.
            if isAppActive && !hasShownInCurrentForeground {
                showAdIfAvailable()
            }
        } catch {
            print("App open ad failed to load with error: \(error.localizedDescription)")
            appOpenAd = nil
            loadTime = nil
        }
    }

    private func showAdIfAvailable(retryAttempt: Int = 0) {
        guard !isShowingAd else { return }

        guard isAdAvailable(),
              let appOpenAd else {
            appOpenAdManagerDelegate?.appOpenAdManagerAdDidComplete(self)
            Task {
                await loadAd()
            }
            return
        }

        isShowingAd = true
        hasShownInCurrentForeground = true
        appOpenAd.fullScreenContentDelegate = self
        appOpenAd.present(from: nil)
    }

    private func retryShowIfNeeded(from attempt: Int) {
        guard isAppActive, attempt < 8 else { return }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.showAdIfAvailable(retryAttempt: attempt + 1)
        }
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        print("App open ad recorded an impression.")
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        print("App open ad recorded a click.")
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("App open ad will be presented.")
    }

    func adWillDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("App open ad will be dismissed.")
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("App open ad was dismissed.")
        isShowingAd = false
        appOpenAd = nil
        loadTime = nil
        appOpenAdManagerDelegate?.appOpenAdManagerAdDidComplete(self)
        Task {
            await loadAd()
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("App open ad failed to present with error: \(error.localizedDescription)")
        isShowingAd = false
        appOpenAd = nil
        loadTime = nil
        appOpenAdManagerDelegate?.appOpenAdManagerAdDidComplete(self)
        Task {
            await loadAd()
        }
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

#if canImport(GoogleMobileAds)
    func applicationDidBecomeActive(_ application: UIApplication) {
        AppOpenAdManager.shared.handleAppDidBecomeActive()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        AppOpenAdManager.shared.handleAppWillResignActive()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        AppOpenAdManager.shared.handleAppDidEnterBackground()
    }
#endif
}

@main
struct FestTimeApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegateProxy.self) var notificationDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ScheduleView()
        }
        .onChange(of: scenePhase) { newPhase in
#if canImport(GoogleMobileAds)
            switch newPhase {
            case .active:
                AppOpenAdManager.shared.handleAppDidBecomeActive()
            case .inactive:
                AppOpenAdManager.shared.handleAppWillResignActive()
            case .background:
                AppOpenAdManager.shared.handleAppDidEnterBackground()
            @unknown default:
                break
            }
#endif
        }
    }
}
