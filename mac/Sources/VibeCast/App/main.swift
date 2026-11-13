// VibeCast 菜单栏服务入口。
// 以 LSUIElement（无 Dock 图标）方式运行，提供菜单栏入口和显式启动时的手机配对窗口。

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // 菜单栏 App，不在 Dock 显示

let delegate = AppDelegate()
app.delegate = delegate
app.run()
