import SwiftUI
import UserNotifications
import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

protocol AppOpenAdManagerDelegate: AnyObject {
    /// Called when the app-open ad lifecycle completes (dismissed or failed to present).
    func appOpenAdManagerAdDidComplete(_ appOpenAdManager: AppOpenAdManager)
}

#if canImport(GoogleMobileAds)
@MainActor
final class AppOpenAdManager: NSObject, FullScreenContentDelegate {
    static let shared = AppOpenAdManager()

    private let appOpenAdUnitID = "ca-app-pub-5696830624450387/8235516537"
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
        MobileAds.shared.start(completionHandler: nil)
        Task {
            await loadAd()
        }
    }

    func handleAppDidBecomeActive() {
        isAppActive = true
        print("App open ad: app became active.")

        guard !hasShownInCurrentForeground else { return }
        showAdIfAvailable()
    }

    func handleAppWillResignActive() {
        isAppActive = false
    }

    func handleAppDidEnterBackground() {
        isAppActive = false
        hasShownInCurrentForeground = false
        print("App open ad: app entered background, session reset.")
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
            appOpenAd = try await AppOpenAd.load(with: appOpenAdUnitID, request: Request())
            appOpenAd?.fullScreenContentDelegate = self
            loadTime = Date()
            print("App open ad loaded successfully.")

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

    private func showAdIfAvailable() {
        guard !isShowingAd else { return }

        guard isAdAvailable(),
              let appOpenAd else {
            print("App open ad is not ready yet.")
            appOpenAdManagerDelegate?.appOpenAdManagerAdDidComplete(self)
            Task {
                await loadAd()
            }
            return
        }

        isShowingAd = true
        appOpenAd.fullScreenContentDelegate = self
        print("App open ad present requested.")
        appOpenAd.present(from: nil)
    }

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {
        print("App open ad recorded an impression.")
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {
        print("App open ad recorded a click.")
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("App open ad will be presented.")
        hasShownInCurrentForeground = true
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
        hasShownInCurrentForeground = false
        appOpenAd = nil
        loadTime = nil
        appOpenAdManagerDelegate?.appOpenAdManagerAdDidComplete(self)
        Task {
            await loadAd()
            if isAppActive && !hasShownInCurrentForeground {
                showAdIfAvailable()
            }
        }
    }
}
#else
@MainActor
final class AppOpenAdManager {
    static let shared = AppOpenAdManager()

    weak var appOpenAdManagerDelegate: AppOpenAdManagerDelegate?

    private init() {}

    func configure() {}

    func handleAppDidBecomeActive() {}

    func handleAppWillResignActive() {}

    func handleAppDidEnterBackground() {}
}
#endif

final class NotificationDelegateProxy: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
    @State private var hasConfiguredAds = false
    @AppStorage("festtime.hasCompletedFirstLaunchSession") private var hasCompletedFirstLaunchSession = false

    var body: some Scene {
        WindowGroup {
            ScheduleView()
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                if !hasConfiguredAds {
                    hasConfiguredAds = true
                    // Configure AdMob only after the first scene becomes active,
                    // so cold launch renders immediately without white/black delay.
                    DispatchQueue.main.async {
                        AppOpenAdManager.shared.configure()
                        if hasCompletedFirstLaunchSession {
                            AppOpenAdManager.shared.handleAppDidBecomeActive()
                        }
                    }

                    // Keep first execution ad-free to protect cold-start UX.
                    if !hasCompletedFirstLaunchSession {
                        hasCompletedFirstLaunchSession = true
                    }
                    return
                }
                AppOpenAdManager.shared.handleAppDidBecomeActive()
            case .inactive:
                AppOpenAdManager.shared.handleAppWillResignActive()
            case .background:
                AppOpenAdManager.shared.handleAppDidEnterBackground()
            @unknown default:
                break
            }
        }
    }
}
