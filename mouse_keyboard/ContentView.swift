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
        .init(keys: "Tab", description: "应用切换模式（方向键选择或数字 ID + 回车）"),
        .init(keys: "Esc", description: "退出控制模式 / 关闭应用切换")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroSection
                shortcutsSection
                permissionSection
            }
            .padding(24)
        }
        .background(Color.appleLightGray)
        .frame(minWidth: 860, minHeight: 620)
    }
}

private extension ContentView {
    var heroSection: some View {
        VStack(spacing: 12) {
            Text("键盘控制鼠标")
                .font(.system(size: 56, weight: .semibold))
                .kerning(-0.28)
                .lineSpacing(2)
                .foregroundStyle(Color.white)

            Text("F8 一键开启，全局键盘驱动鼠标与滚轮。")
                .font(.system(size: 21, weight: .regular))
                .kerning(0.23)
                .foregroundStyle(Color.white.opacity(0.9))

            HStack(spacing: 10) {
                Text("Learn more >")
                    .font(.system(size: 14, weight: .regular))
                    .kerning(-0.22)
                    .foregroundStyle(Color.appleBrightBlue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .stroke(Color.appleBrightBlue, lineWidth: 1)
                    )

                Text("F8")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.appleBlue)
                    )
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 42)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    var shortcutsSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("按键")
                    .font(.system(size: 17, weight: .semibold))
                    .kerning(-0.37)
                    .frame(width: 220, alignment: .leading)

                Text("中文说明")
                    .font(.system(size: 17, weight: .semibold))
                    .kerning(-0.37)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Color.appleNearBlack)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.white)

            ForEach(shortcutItems) { item in
                HStack(alignment: .top, spacing: 12) {
                    Text(item.keys)
                        .font(.system(size: 17, weight: .regular, design: .monospaced))
                        .frame(width: 220, alignment: .leading)
                        .foregroundStyle(Color.appleNearBlack)

                    Text(item.description)
                        .font(.system(size: 17, weight: .regular))
                        .kerning(-0.37)
                        .foregroundStyle(Color.black.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white)

                if item.id != shortcutItems.last?.id {
                    Divider()
                        .background(Color.black.opacity(0.08))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
    }

    var permissionSection: some View {
        HStack(spacing: 10) {
            Text("首次运行请授权：系统设置 > 隐私与安全性 > 辅助功能（必要时也开启输入监控）。")
                .font(.system(size: 14, weight: .regular))
                .kerning(-0.22)
                .foregroundStyle(Color.black.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension Color {
    static let appleLightGray = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    static let appleNearBlack = Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255)
    static let appleBlue = Color(red: 0 / 255, green: 113 / 255, blue: 227 / 255)
    static let appleBrightBlue = Color(red: 41 / 255, green: 151 / 255, blue: 255 / 255)
}

#Preview {
    ContentView()
}
