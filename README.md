# mouse_keyboard

一个 macOS 菜单栏小工具：用键盘控制鼠标移动、点击和滚轮。

## 功能

- `F8`：开启 / 关闭控制模式
- `W / A / S / D`：移动鼠标
- `Y`（按住）：加速移动
- `H`（按住）：减速微调
- `I / O`：左键 / 右键单击
- `J / K`：滚轮下 / 上（可在菜单中反转）
- `- / = / [ / ]`：快速定位到当前屏幕四象限中心
- `1 / 2 / 3`：快速跳转到第 1 / 2 / 3 屏幕中心（不存在会提示）
- `Esc`：退出控制模式

额外功能：

- 菜单栏启用/禁用
- 速度档位（Slow / Normal / Fast）
- 开机启动（Launch at Login）
- 中英文国际化（部分文案）

---

## 运行环境

- macOS 13+
- Xcode 15+（建议）

---

## 从源码安装（给拉代码的人）

> 不需要加入 Apple 开发者计划，也可以在自己机器上安装运行。

### 1. 克隆仓库

```bash
git clone git@github.com:nickcxm/mouse_keyboard.git
cd mouse_keyboard
```

### 2. 用 Xcode 打开工程

- 打开 `mouse_keyboard.xcodeproj`
- 选择一个本机签名团队（免费 Apple ID 也可以）

### 3. 本机构建运行（调试）

- 在 Xcode 里 `Run`（`Cmd + R`）
- 首次运行会请求权限

### 4. 首次授权（必须）

打开系统设置，给 App 权限：

- `Privacy & Security > Accessibility`：开启
- 如按键拦截不稳定，再开启：
  - `Privacy & Security > Input Monitoring`

### 5. 安装为本地 App（推荐）

为了稳定使用“开机启动”，建议安装到 `/Applications`：

1. Xcode 菜单 `Product -> Archive`
2. 归档完成后点 `Distribute App`
3. 选择 `Copy App`
4. 导出 `mouse_keyboard.app`
5. 拖到 `/Applications`（或 `~/Applications`）
6. 从安装位置启动一次，并再次确认权限

---

## 使用说明

1. 启动后，菜单栏会出现图标  
2. 按 `F8` 进入控制模式  
3. 使用上面的按键控制鼠标  
4. 按 `Esc` 或再次按 `F8` 退出

---

## 常见问题

### Q1: 为什么按键没反应？

- 通常是权限未开完整。请检查：
  - Accessibility
  - Input Monitoring

### Q2: 为什么无法开启“开机启动”？

- 如果是直接从 Xcode 调试目录运行，系统可能拒绝注册登录项。
- 请按上面的安装步骤导出并放到 `/Applications` 后再开启。

### Q3: J/K 滚动方向和系统不一致？

- 菜单栏里打开 `Invert J/K Scroll` 即可反转，仅影响键盘 J/K，不影响物理鼠标滚轮。

---

## 免责声明

本工具会拦截全局键盘事件并模拟鼠标输入，仅用于个人效率提升，请在可信环境下使用。

