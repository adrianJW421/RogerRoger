# RogerRoger Android 麦克风

原生 Android 客户端, 使用手机已有的搜狗输入法小米版识别语音, 实时同步到 Mac 当前光标. 界面不展示转写文本或输入法面板. 大按钮完成「开始说话 → 停止 → 发送 (Enter)」.

## 构建

需要 Java 17、Android SDK Platform 36、Build Tools 36.0.0. 设置 `VIBECAST_JAVA_HOME` / `VIBECAST_ANDROID_HOME`, 或在 Git 忽略的 `.local/toolchain.json` 配置 `javaHome` / `androidHome`. 显式 VIBECAST 环境变量优先, 其次本机配置, 再回退到 JAVA_HOME 与 ANDROID_HOME / ANDROID_SDK_ROOT.

```bash
python3 fetch_deps.py
python3 build.py
```

构建先运行 56 条纯 Java 逻辑断言, 再编译并签名. Maven 固定依赖及校验值在 dependencies.json. 输出 `dist/RogerRoger-Mic-0.1.3.apk`, 对应元数据在 `dist/build-info.json`.

`.local/preview.keystore` 是本地预览签名密钥, 不提交 Git; 更新现有安装必须使用同一密钥. 当前包 debuggable=true, 不代表已完成正式发行签名准备.

## 连接与行为

Mac 需要支持 follow_current / focus_context / currentAppEnterSupported, 原上游 v0.4.0 不具备这些扩展. 在「连接设置」粘贴 Mac 提供的完整手机链接. 链接保存于 App 私有存储, 不写入源码或 APK.

- 只有 INTERNET 权限, 本 App 不采集或向 Mac 发送音频; 录音由已授权的手机搜狗完成, 搜狗可能使用云端识别.
- 使用隐藏 EditText + WindowInsetsAnimationController + 小米搜狗语音广播. 当前验证环境为 Android 17 与搜狗小米版 10.32.21.202609081832.
- 录音真实就绪后才显示绿色提示. 停止后保留输入会话 2–4.5 秒, 再接收 0.6–1.6 秒迟到文字; 界面明确提示收尾期间麦克风仍可能开启.
- 点发送后等待收尾和最终文本 ACK, 在原 Mac 会话按一次 Enter; 目标变化取消排队, 结果未知不自动重试.
- 需要保持 App 前台. 离开 App、断线或其他控制端接管时停止. 诊断只保存计数/时序/状态, 不记录转写或 token.

本轮更名保留 Android package `local.vibecast.mic`, 现有预览签名与协议兼容. 显示名为「RogerRoger 麦克风」, 版本 0.1.3 / code 4.

## 致谢

本客户端的协议与分段算法基于 [VibeCast](https://github.com/Pls-1q43/VibeCast). 保留 [MIT LICENSE](LICENSE), 第三方依赖许可见 [NOTICE](NOTICE.md). 不包含搜狗 APK、模型或专有代码.
