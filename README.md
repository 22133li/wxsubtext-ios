# 潜台词 iOS 版（微信 8.0.78，Dopamine + roothide）

Android Xposed 版 `WxSubtext V1.7` 的 iOS 移植。核心逻辑（prompt / 脱敏 / 网络 / JSON 解析 / 上下文缓冲 / 限流 / 卡片 UI）已完整移植；Hook 层采用运行时发现，不硬编码微信混淆类名。

## 目录
- `Tweak.x` / `Makefile` / `control` / `wxsubtext.plist`：Theos 工程（注入 `com.tencent.xin`）
- `Core/`：WXSubtextConfig（CFPreferences 配置）、WXSubtextDesensitizer（脱敏）、WXSubtextPrompt（prompt 原文）、WXSubtextNetwork（NSURLSession）、WXSubtextAnalysis（JSON 模型）、WXSubtextCore（编排：缓冲/去重/缓存/限流/卡片）
- `UI/`：WXSubtextCardView（分析卡片：心情条/风险/4 解读/复制回复/重试）
- `Hook/`：WXSubtextHook（聊天页发现 + cell 文本抓取 + 方向判定）
- `frida/dump_chat.js`：在手机上 dump 聊天界面结构，用于收紧 hook
- `config-sample.plist`：配置示例

## 构建
- GitHub Actions：`.github/workflows/build.yml`，macOS + Theos，产物为 `.deb`
- 手机端：theosinstaller 建工程后把本目录文件拷进去 `make package`

## 配置（微信内设置 / Filza 编辑）

1.01+：微信「我 → 设置」最下方会出现「潜台词」入口，点进去直接改：总开关、API Key、接口地址、
模型、默认关系、脱敏开关、分析所有单聊、白名单（每行一个备注名）、自定义敏感词、限流参数。
修改实时生效，无需重启微信。

也可以用 Filza 直接编辑 `/var/mobile/Library/Preferences/com.haoran.wxsubtext.plist`，键：
`Enabled`(bool) `APIKey`(string) `BaseURL`(string，默认 DeepSeek) `Model`(string，默认 deepseek-chat)
`RelationDefault`(string，默认"亲密关系（伴侣）") `Desensitize`(bool) `SensitiveWords`(array)
`ContextSize`(int，默认5) `CollapseToTop1`(bool) `OnlyLatest`(bool) `MaxCallsPerHour`(int，默认60)
`TimeoutMs`(int，默认30000) `AnalyzeAllContacts`(bool，默认NO) `EnabledTalkers`(array，会话标题白名单)

默认只分析白名单里的单聊；群聊（标题以 `(数字)` 结尾）自动跳过。

## 测试
1. 装 deb 后打开微信，进任意单聊，让对方发一条文本（或自己小号发）
2. 日志：`log stream --predicate 'process == "WeChat"' | grep WXSubtext` 或看 `/var/mobile/Documents`
3. 期望看到：`进入聊天页` → `抓到消息 dir=对方` → 卡片出现在气泡下方

## 收紧 hook（重要）
首次运行是启发式发现，可能误判。跑一遍 `frida/dump_chat.js`：
`frida -U -f com.tencent.xin -l frida/dump_chat.js`，打开单聊后把 `[WXDUMP]` 输出贴回，
即可把 `looksLikeChatVC` 里的启发式换成精确类名。

## 已知限制（v1）
- 卡片是浮层（锚定在气泡下方），滚动时自动关闭；未做成 Android 那种嵌入消息行的形式
- 未移植：联系人白名单 UI（用 plist 手工配）、SQLCipher 读微信数据库（Android 版默认关闭，iOS 首版不做）
