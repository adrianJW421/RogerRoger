# RogerRoger

手机上说话, 文字实时出现在 Mac 当前光标. 说完点「停止」, 再点「发送 (Enter)」.

RogerRoger 使用手机上已有的搜狗输入法小米版完成语音识别, Mac 只接收文字并写入当前输入框. 手机原生 App 只有大按钮和连接状态, 不展示转写草稿、键盘或搜狗语音面板.

## 功能

- **跟随 Mac 光标**: 切换应用、输入框或光标后自动跟随, 不带入旧草稿, 不拉回旧应用.
- **渐进写入**: 保留未变的文字前缀, 避免每次识别更新都全选整段文字.
- **保留搜狗效果**: 直接使用手机已安装的搜狗输入法, 不在 Mac 上运行 ASR. 搜狗本身可能使用其云端识别.
- **真实就绪提示**: 检测到录音就绪且 Mac 存在输入光标后, 显示绿色「可以说话」并轻震.
- **句尾收尾**: 停止后短暂保留输入会话接收句尾, 界面会提示此时麦克风仍可能开启.
- **手机按 Enter**: 停止后可以立即点发送, 等收尾和最终文字同步确认后再按一次 Enter. 换目标会取消排队发送, 结果未知不自动重试.

## 使用

1. 下载 [macOS 安装包](https://github.com/adrianJW421/RogerRoger/releases/tag/v0.4.1), 打开 DMG, 把 RogerRoger 拖到 Applications, 再从应用程序启动.
2. 配对窗口会自动打开. 手机与 Mac 连接同一个 Wi-Fi, 用手机扫码工具识别二维码并复制完整链接, 粘贴到 Android App「连接设置」; 也可以在 Mac 点击「复制配对链接」. 按窗口提示开启辅助功能权限.
3. 在 Mac 点进要输入的文本框.
4. 手机点「开始说话」, 等绿色提示后开口.
5. 说完点停止; 可以马上点「发送 (Enter)」, App 会自动等待收尾与同步.

发送按钮等同于目标输入框中的 Enter. 目标应用把 Enter 解释为发送还是换行, 遵循该应用本来的设置.

关闭配对窗口后服务仍在菜单栏运行; 再次双击 App 或选择菜单栏「连接手机」可重新打开. 登录自启动和连接状态刷新不会弹窗或抢输入焦点. Android 0.1.3 尚无内置扫码器, 扫码后需复制链接到 App, 不会自动跳转配对.

Mac 包为本地签名的未公证预览版. 如果系统阻止首次打开, 先尝试启动一次, 再到「系统设置 → 隐私与安全性」对 RogerRoger 选择「仍要打开」. 参见 [Apple 的首次打开说明](https://support.apple.com/en-us/102445). 无需关闭系统整体安全检查.

## 当前支持范围

原生客户端已在小米折叠屏、Android 17、搜狗输入法小米版 `10.32.21.202609081832` 上验证. 使用小米/搜狗专用语音入口, 不代表其他输入法或手机型号均受支持. 手机 App 需要保持前台.

Mac 要求 macOS 13+ 与可编辑的辅助功能输入控件. 推荐使用「当前应用」路径; 上游固定应用卡片保留兼容, 不在本轮完整验收范围内.

Android 安装包见 [0.1.3 预览版 Release](https://github.com/adrianJW421/RogerRoger/releases/tag/android-v0.1.3), 最低 Android 12. Mac 通用安装包见 [0.4.1 Release](https://github.com/adrianJW421/RogerRoger/releases/tag/v0.4.1), 支持 Apple Silicon 与 Intel. 已有 VibeCast 0.1.2 Android 安装可使用同一签名的 RogerRoger 0.1.3 覆盖更新.

## 构建

### macOS

需要 Node.js 18+、Swift 5.9+ 与 Xcode Command Line Tools 或 Xcode.

```bash
cd web
npm ci
npm test
npm run typecheck
cd ..
VERSION=0.4.1 BUILD_NUMBER=10.8 SWIFT_ARCHS="arm64 x86_64" bash scripts/build_app.sh
```

输出 `dist/RogerRoger.app` 与 `dist/RogerRoger-0.4.1-macos.zip`. Intel / 通用包可按工具链情况设置 `SWIFT_ARCHS`.

可分发 DMG 使用 `bash scripts/build_macos_dmg.sh`, 从当前 Git 提交的干净源码构建, 输出 `dist/RogerRoger-0.4.1-macos-universal.dmg`. 未提交的改动和本地资料不进入此产物.

默认不配置 Sparkle 更新源, 自动更新关闭. 如需发布自动更新, 配置自己的 `APPCAST_URL` 与 `SPARKLE_PUBLIC_ED_KEY`, 不使用上游项目的签名或更新源.

### Android

需要 JDK 17、Android SDK Platform 36、Build Tools 36.0.0.

```bash
cd android
export VIBECAST_JAVA_HOME=/path/to/jdk17
export VIBECAST_ANDROID_HOME=/path/to/android-sdk
python3 fetch_deps.py
python3 build.py
```

输出 `android/dist/RogerRoger-Mic-0.1.3.apk`. 这是已关闭调试的预览包, 构建工具会生成仅保存在本地的校验记录. 本地签名密钥保存在 Git 忽略的 `android/.local/`, 更新已安装包需要保留同一密钥. 详见 [Android 构建说明](android/README.md).

## 开发文档

- [同步协议](shared/protocol.md): 自动跟随、文本确认、显式 Enter.
- [Android 客户端](android/README.md): 工具链、签名、运行限制.

`mac/`、`web/`、`android/` 分别为 Mac、网页和原生手机客户端. 部分内部包名、Bundle ID、数据目录和协议标识保留 VibeCast 名称, 以延续已有配对、配置与授权; 产品显示名和构建产物使用 RogerRoger. 其他历史 docs/marketing 文件保留上游记录, 当前行为以此 README 与代码为准.

## 致谢与许可证

RogerRoger fork 自 [VibeCast](https://github.com/Pls-1q43/VibeCast), 基于 v0.4.0. 感谢 Jeffrey Wang 和原项目提供的基础实现. 原 MIT 版权声明保留在 [LICENSE](LICENSE), 第三方依赖见 [NOTICE](android/NOTICE.md).

搜狗应用、识别引擎、模型和专有代码不随本项目分发; 客户端只调用手机已经安装的输入法.
