import SwiftUI

struct ContentView: View {
    private struct ShortcutItem: Identifiable {
        let id = UUID()
        let keys: LocalizedStringKey
        let description: LocalizedStringKey
    }

    private let shortcutItems: [ShortcutItem] = [
        .init(keys: "F8", description: "开启或关闭键盘控制模式"),
        .init(keys: "W / A / S / D", description: "移动鼠标（上 / 左 / 下 / 右）"),
        .init(keys: "Y（按住）", description: "加速移动"),
        .init(keys: "H（按住）", description: "减速微调"),
        .init(keys: "J / K", description: "滚轮下 / 上（可在菜单里反转）"),
        .init(keys: "I / O", description: "左键单击 / 右键单击"),
        .init(keys: "-  =  [  ]", description: "定位到当前屏幕四个象限中心"),
        .init(keys: "1 / 2 / 3", description: "跳转到第 1 / 2 / 3 块显示器中心"),
        .init(keys: "Esc", description: "退出控制模式")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("键盘控制鼠标")
                .font(.title)
                .bold()

            Text("以下快捷键在控制模式下生效：")
                .font(.headline)

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Text("按键")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 180, alignment: .leading)
                    Text("中文说明")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.06))

                ForEach(shortcutItems) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Text(item.keys)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 180, alignment: .leading)

                        Text(item.description)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.primary.opacity(0.02))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )

            Text("首次运行请授权：系统设置 > 隐私与安全性 > 辅助功能（必要时也开启输入监控）。")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 460)
    }
}

#Preview {
    ContentView()
}
