import SwiftUI
import CoreBluetooth
import AVFoundation


public class MainDelegate: UIResponder, UIApplicationDelegate, UIWindowSceneDelegate, UNUserNotificationCenterDelegate {
    
    override init() {
        super.init()
        CGMManager.shared.setUp()
    }

    // FIXME: iOS 14: launchOptions empty
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            if shortcutItem.type == "NFC" {
                CGMManager.shared.startNFCSession()
            }
        }
        return true
    }

    public func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let sceneConfiguration = UISceneConfiguration(name: "LaunchConfiguration", sessionRole: connectingSceneSession.role)
        sceneConfiguration.delegateClass = MainDelegate.self
        return sceneConfiguration
    }

    public func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        if shortcutItem.type == "NFC" {
            CGMManager.shared.startNFCSession()
        }
        completionHandler(true)
    }

}
