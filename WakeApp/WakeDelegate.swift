import UIKit

@main
final class WakeDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        WakeRelay.shared.bind()
        let pid = ProcessInfo.processInfo.processIdentifier
        let stateWord = stateWord(application.applicationState)
        WakeLog.appendLine("进程启动 pid=\(pid) 状态=\(stateWord)")
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        WakeRelay.shared.noteBackground(application)
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        WakeRelay.shared.storeHook(completionHandler)
        WakeRelay.shared.bind()
        WakeRelay.shared.noteWake(identifier)
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(
            name: "Default",
            sessionRole: connectingSceneSession.role
        )
        sceneConfig.delegateClass = WakeScene.self
        return sceneConfig
    }

    private func stateWord(_ state: UIApplication.State) -> String {
        switch state {
        case .active:
            return "前台"
        case .inactive:
            return "非活动"
        case .background:
            return "后台"
        @unknown default:
            return "其他"
        }
    }
}
