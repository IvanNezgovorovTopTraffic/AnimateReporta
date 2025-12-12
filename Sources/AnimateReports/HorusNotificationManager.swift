import Foundation
import UIKit
import UserNotifications
import OneSignalFramework

// MARK: -- Horus Notification Manager

/// Менеджер для интеграции OneSignal в сторонние проекты (бог Хорус)
public final class HorusNotificationManager {
    public static let shared = HorusNotificationManager()
    
    private init() {}
    
    // MARK: -- Private Properties
    
    private let launchCountKey = "animationGalaxyLaunchCount"
    
    // MARK: - Public Functions
    
    /// Инициализация OneSignal
    /// - Parameters:
    ///   - appId: OneSignal App ID
    ///   - launchOptions: launchOptions из AppDelegate
    public func configure(appId: String, launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        
        OneSignal.initialize(appId, withLaunchOptions: launchOptions)
        let userId = PharaohGate.getUserID()
        let launchCount = UserDefaults.standard.integer(forKey: launchCountKey)
        OneSignal.login(userId)
        
        
        schedulePermissionFlow(userId: userId, launchCount: launchCount)
        UserDefaults.standard.set(launchCount + 1, forKey: launchCountKey)
    }
    
    // MARK: - Private Functions
    
    private func schedulePermissionFlow(userId: String, launchCount: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            
            if launchCount == 0 {
                self.requestInitialPermission(userId: userId)
            } else {
                self.checkNotificationStatus(userId: userId, launchCount: launchCount)
            }
        }
    }
    
    private func requestInitialPermission(userId: String) {
        OneSignal.Notifications.requestPermission { accepted in
            print("✅ OneSignal push permission accepted: \(accepted)")
            if accepted {
                OneSignal.login(userId)
                print("📥 OneSignal login on accepted")
            }
        }
    }
    
    private func checkNotificationStatus(userId: String, launchCount: Int) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    OneSignal.login(userId)
                    print("📬 OneSignal login authorized")
                case .denied, .notDetermined:
                    if launchCount < 2 {
                        PharaohGate.showNotificationsAlert()
                    }
                    print("⚠️ Show notifications alert")
                @unknown default:
                    if launchCount < 2 {
                        PharaohGate.showNotificationsAlert()
                    }
                    print("⚠️ Unknown status, show alert")
                }
            }
        }
    }
}

