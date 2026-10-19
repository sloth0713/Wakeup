import SwiftUI

struct WakeBoard: View {
    @ObservedObject private var relay = WakeRelay.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusCard
                    guideCard
                    actionCard
                    logCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("后台拉活")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { relay.reloadLines() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                relay.reloadLines()
            }
        }
    }

    private var statusCard: some View {
        card {
            Text(relay.hint)
                .font(.title3.weight(.semibold))
                .foregroundStyle(hintColor)
            Text("当前进程 \(ProcessInfo.processInfo.processIdentifier)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if relay.woken {
                Text("已记录到 Background URLSession 拉起")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            if relay.fraction > 0 {
                Text("下载进度 \(Int(relay.fraction * 100))%")
                    .font(.subheadline)
                ProgressView(value: relay.fraction)
            }
        }
    }

    private var guideCard: some View {
        card {
            Text("怎么演练")
                .font(.headline)
            Text("必须用真机。模拟器不会被后台会话拉起。请先安装，再从桌面图标打开，不要挂着 Xcode 调试器演练。")
            Text("关闭低电量模式，尽量连 Wi-Fi。默认只下载约 2MB，完成后才会拉起，不用等 200MB。")
            Text("点开始后若出现通知权限，请允许。看到提示就马上回到桌面，不要在多任务界面上滑划掉。")
            Text("进入后台后才会注册下载。注册成功后 App 会立刻结束自己的进程。下载完成后，系统再拉起，日志里会出现新的 pid 和 handleEventsForBackgroundURLSession。")
            Text("从多任务划掉会取消后台传输，不会拉活。")
                .foregroundStyle(.orange)
        }
        .font(.subheadline)
    }

    private var actionCard: some View {
        card {
            Text("下载地址")
                .font(.headline)
            TextField("https://", text: $relay.remoteText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .font(.footnote)
                .disabled(relay.armed || relay.asking)
            Button {
                relay.arm()
            } label: {
                Text(buttonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(relay.armed || relay.asking)
            if relay.armed {
                Button("取消演练") {
                    relay.disarm()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var logCard: some View {
        card {
            HStack {
                Text("日志")
                    .font(.headline)
                Spacer()
                Button("清空") {
                    WakeLog.clear()
                    relay.reloadLines()
                }
                .font(.subheadline)
            }
            if relay.lines.isEmpty {
                Text("还没有日志")
                    .foregroundStyle(.secondary)
            } else {
                Text(relay.lines.joined(separator: "\n"))
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var buttonTitle: String {
        if relay.asking {
            return "正在请求通知权限…"
        }
        if relay.armed {
            return "等待回到桌面…"
        }
        return "开始演练"
    }

    private var hintColor: Color {
        if relay.woken {
            return .green
        }
        if relay.armed {
            return .orange
        }
        return .primary
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
