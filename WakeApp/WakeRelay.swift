import Combine
import Darwin
import UIKit
import UserNotifications

final class WakeRelay: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = WakeRelay()
    static let sessionMark = "com.demo.WakeApp.relay"
    static let defaultRemote = "https://speed.cloudflare.com/__down?bytes=2097152"
    private static let wakeKey = "wasWoken"
    private static let remoteKey = "remoteURL"

    @Published var remoteText = WakeRelay.defaultRemote
    @Published var hint = "阅读步骤后开始演练"
    @Published var lines: [String] = []
    @Published var fraction = 0.0
    @Published var armed = false
    @Published var asking = false
    @Published var woken = false

    private var session: URLSession?
    private var finishHook: (() -> Void)?
    private var started = false
    private var decided = false
    private let hookLock = NSLock()
    private let fractionLock = NSLock()
    private var lastFraction = 0.0

    private override init() {
        super.init()
        woken = UserDefaults.standard.bool(forKey: Self.wakeKey)
        if let saved = UserDefaults.standard.string(forKey: Self.remoteKey), saved.isEmpty == false {
            remoteText = saved
        }
    }

    func bind() {
        guard session == nil else { return }
        let setup = URLSessionConfiguration.background(withIdentifier: Self.sessionMark)
        setup.sessionSendsLaunchEvents = true
        setup.isDiscretionary = false
        setup.allowsCellularAccess = true
        setup.allowsConstrainedNetworkAccess = true
        setup.allowsExpensiveNetworkAccess = true
        setup.waitsForConnectivity = true
        setup.timeoutIntervalForRequest = 60
        setup.timeoutIntervalForResource = 30 * 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "wake.relay.queue"
        session = URLSession(configuration: setup, delegate: self, delegateQueue: queue)
        WakeLog.appendLine("已绑定后台会话 \(Self.sessionMark)")
    }

    func arm() {
        guard asking == false else { return }
        asking = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.asking = false
                if let error {
                    WakeLog.appendLine("通知授权失败：\(error.localizedDescription)")
                } else if granted {
                    WakeLog.appendLine("通知已授权，等待进入后台")
                } else {
                    WakeLog.appendLine("通知未授权，仍会演练，拉活结果只写在日志里")
                }
                self.woken = false
                UserDefaults.standard.set(false, forKey: Self.wakeKey)
                self.fraction = 0
                self.started = false
                self.decided = false
                self.armed = true
                self.hint = "现在回到桌面。进入后台后会注册下载并立刻结束进程"
            }
        }
    }

    func disarm() {
        armed = false
        started = false
        decided = true
        hint = "已取消演练"
        session?.getAllTasks { tasks in
            tasks.forEach { $0.cancel() }
        }
        WakeLog.appendLine("已取消演练")
    }

    func noteBackground(_ application: UIApplication) {
        guard armed else {
            WakeLog.appendLine("进入后台")
            return
        }
        armed = false
        decided = false
        let token = application.beginBackgroundTask(withName: "wake.hand") {
            WakeLog.appendLine("系统收回后台时间")
        }
        WakeLog.appendLine("已进入后台，开始注册下载任务")
        guard registerTransfer() else {
            decided = true
            closeToken(application, token)
            return
        }
        decided = true
        let pid = ProcessInfo.processInfo.processIdentifier
        WakeLog.appendLine("任务已注册，立刻结束进程 pid=\(pid)")
        DispatchQueue.main.async {
            kill(getpid(), SIGKILL)
        }
    }

    private func registerTransfer() -> Bool {
        guard started == false else { return false }
        let trimmed = remoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let remote = URL(string: trimmed), remote.scheme == "https" else {
            armed = false
            hint = "请填写 https 下载地址"
            WakeLog.appendLine("地址无效，未创建任务")
            return false
        }
        started = true
        UserDefaults.standard.set(trimmed, forKey: Self.remoteKey)
        bind()
        guard let session else {
            started = false
            hint = "后台会话创建失败"
            return false
        }
        resetFractionGate()
        fraction = 0
        let task = session.downloadTask(with: remote)
        task.priority = URLSessionTask.highPriority
        task.resume()
        WakeLog.appendLine("已在后台注册下载 task=\(task.taskIdentifier)，约 2MB")
        hint = "任务已注册，立刻结束进程"
        return true
    }

    func storeHook(_ hook: @escaping () -> Void) {
        hookLock.lock()
        finishHook = hook
        hookLock.unlock()
    }

    func noteWake(_ mark: String) {
        UserDefaults.standard.set(true, forKey: Self.wakeKey)
        let pid = ProcessInfo.processInfo.processIdentifier
        WakeLog.appendLine("系统调用 handleEventsForBackgroundURLSession（\(mark)），进程被拉起 pid=\(pid)")
        DispatchQueue.main.async {
            self.woken = true
            self.hint = "已被 Background URLSession 拉起"
        }
        notifyWake()
    }

    func reloadLines() {
        lines = WakeLog.readLines()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let next = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        guard shouldPublish(next) else { return }
        DispatchQueue.main.async {
            self.fraction = next
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        WakeLog.appendLine("下载完成")
        DispatchQueue.main.async {
            self.fraction = 1
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            self.started = false
            if error != nil {
                self.hint = "下载失败"
            } else if self.woken == false && self.decided == false {
                self.hint = "下载在进程结束前已完成，系统不会再拉起"
            }
        }
        if let error {
            WakeLog.appendLine("任务失败：\(error.localizedDescription)")
        } else {
            WakeLog.appendLine("任务完成")
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        WakeLog.appendLine("后台事件已全部派发，通知系统可以挂起")
        runHook()
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        guard let error else { return }
        WakeLog.appendLine("会话失效：\(error.localizedDescription)")
    }

    private func runHook() {
        hookLock.lock()
        let hook = finishHook
        finishHook = nil
        hookLock.unlock()
        DispatchQueue.main.async {
            hook?()
        }
    }

    private func notifyWake() {
        let content = UNMutableNotificationContent()
        content.title = "进程已拉活"
        content.body = "Background URLSession 重新启动了本 App"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                WakeLog.appendLine("通知发送失败：\(error.localizedDescription)")
            } else {
                WakeLog.appendLine("已发送拉活通知")
            }
        }
    }

    private func closeToken(_ application: UIApplication, _ token: UIBackgroundTaskIdentifier) {
        guard token != .invalid else { return }
        application.endBackgroundTask(token)
    }

    private func shouldPublish(_ next: Double) -> Bool {
        fractionLock.lock()
        defer { fractionLock.unlock() }
        guard next - lastFraction >= 0.01 else { return false }
        lastFraction = next
        return true
    }

    private func resetFractionGate() {
        fractionLock.lock()
        lastFraction = 0
        fractionLock.unlock()
    }
}
