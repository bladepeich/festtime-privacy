import SwiftUI
import UserNotifications
import UIKit
import GoogleMobileAds

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

    func applicationDidBecomeActive(_ application: UIApplication) {
        AppOpenAdManager.shared.handleAppDidBecomeActive()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        AppOpenAdManager.shared.handleAppWillResignActive()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        AppOpenAdManager.shared.handleAppDidEnterBackground()
    }
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
        }
    }
}
