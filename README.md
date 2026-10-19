# 后台拉活

iOS 演示工程。用户退到后台后，App 注册一个 Background URLSession 下载，然后自己结束进程。下载完成后，系统重新拉起进程。

## 怎么演练

1. 用真机运行。模拟器不会被后台会话拉起。
2. 从桌面图标打开，不要挂着 Xcode 调试器。
3. 关闭低电量模式，尽量连接 Wi-Fi。
4. 点「开始演练」。若弹出通知权限，请允许。
5. 回到桌面。不要从多任务界面上滑划掉。
6. 进入后台后才会注册约 2MB 的下载。注册成功后，App 会立刻结束自己的进程。
7. 下载由系统调度，完成后才会拉起。日志里会出现新的进程号，以及 `handleEventsForBackgroundURLSession`。

从多任务界面划掉会被当成用户主动终止。系统会取消后台传输，不会拉起，下次打开会看到 `NSURLErrorDomain` 错误 `-999`。

## 工程

用 Xcode 打开 `WakeApp.xcodeproj`，在 Signing 里选择开发团队，目标选这台 iPhone，再点 Run。部署目标是 iOS 17。

Bundle ID 是 `com.demo.WakeApp`。后台会话标识是 `com.demo.WakeApp.relay`。

## 日志

统一过滤关键字是 `WakeRelay`。

系统控制台里，子系统是 `com.demo.WakeApp`，分类是 `WakeRelay`。

拉起成功时会看到：

```text
[WakeRelay] 系统调用 handleEventsForBackgroundURLSession（com.demo.WakeApp.relay），进程被拉起 pid=新进程号
```

结束进程那一行的 pid，和拉起那一行的 pid 不同。只有 `进程启动 … 状态=前台`、没有 `handleEventsForBackgroundURLSession`，表示是自己打开的，不是被唤醒的。
