# Codex Touch Bar Pet

把 MacBook Pro 的 Touch Bar 变成 Codex 小伙伴：查看额度、工作状态，让宠物跟着任务动起来。

[English](README.md) · [下载](https://github.com/CsokiW/codex-touchbar-pet/releases) · [反馈问题](https://github.com/CsokiW/codex-touchbar-pet/issues)

由 [CsokiW](https://github.com/CsokiW) 维护，基于 [wjx8/CodexBar](https://github.com/wjx8/CodexBar) 修改；更早的基础来自 [Jack Chen / TouchBarCodexToken](https://github.com/jackchensky/TouchBarCodexToken)。这是社区项目，与 OpenAI、Apple 没有官方隶属关系。

![Touch Bar 界面](docs/touchbar-preview.png)

上图由真实原生界面使用示例额度渲染，不包含个人账号数据。

## 这个版本有什么不同

- **王臭吉陪你工作**：内置作者创作的宠物。工作、等待回应、出错和完成时切换动作，点一下还能打招呼。
- **真实任务状态**：读取 Codex Desktop 本机运行状态，不从聊天措辞猜测。跟踪近期 40 个未归档本地任务，并继续跟踪此前已订阅且仍在运行或等待的旧任务，并非只显示当前选中任务。
- **额度一眼看清**：5 小时、周额度、剩余百分比、重置时间；账号提供重置券时显示相关信息。
- **一个按钮跟随场景**：在 Codex 里刷新额度，切到其他软件后点击返回 Codex；有待处理项或错误时突出显示。
- **中文语音输入**：点击麦克风开始说话，再点一次切回 Codex，核对可编辑文本框后输入；无法确认目标时保留文字，供你重试。
- **显示恢复**：切换软件时保留 Touch Bar 面板；唤醒后尝试恢复，锁屏、休眠和菜单手动隐藏时不会强行展示。

额度与语音功能继承自上游。本版本主要新增宠物、任务状态、完成动画、场景按钮和显示恢复。为了放下这些内容，Touch Bar 不再显示上游的“昨日／累计 token”列。内部读取计时字段辅助判断任务完成，当前紧凑界面不单独显示耗时计数器。

## 安装与使用

需要实体 Touch Bar MacBook Pro、macOS 12 或更新版本，以及已登录且能正常运行的 Codex Desktop／承载 Codex 的 ChatGPT 桌面应用。macOS 12 是构建目标，不代表所有系统版本均经过实机测试。当前主要验证 Intel 版本；Apple Silicon 可在本机编译，尚未实机验证。任务状态依赖 Codex 私有 IPC 和本地数据库，后续桌面应用更新可能需要适配。

当前界面及权限提示以中文为主。本轮本机构建与模拟测试环境为 Intel MacBook Pro、macOS 26.6.2，已安装的 ChatGPT 桌面版本为 26.1013.40934；不代表跨系统兼容或语音端到端实测通过。

从[下载页](https://github.com/CsokiW/codex-touchbar-pet/releases)获取匹配架构的压缩包，校验 SHA-256，解压后把 **Codex Touch Bar Pet.app** 放入应用程序目录并打开。首次打开会注册用户级自动启动项，之后随 Codex 启停。切到浏览器仍保留 Touch Bar；顶部菜单可以隐藏、重新加载、刷新或退出。

校验 0.2.2 下载文件时，将压缩包和校验清单放在同一个目录，再运行：

```bash
shasum -a 256 -c Codex-Touch-Bar-Pet-0.2.2-SHA256SUMS.txt
```

手动退出只抑制当前 Codex 宿主会话的自动启动；重新打开 Codex 后恢复跟随，即使两次检查之间发生了快速重启。

应用未经过 Apple 公证。如果系统拦截，请检查来源后，通过“系统设置 → 隐私与安全性”的“仍要打开”单独放行。不要全局关闭系统安全保护。

同一时间只运行一个 Touch Bar 替换工具。新应用有独立名称、标识符和启动项，不会覆盖其他 CodexBar。

源码安装：

```bash
git clone https://github.com/CsokiW/codex-touchbar-pet.git
cd codex-touchbar-pet
bash scripts/test.sh
bash scripts/build-app.sh
open 'build/Codex Touch Bar Pet.app'
```

构建需要 Xcode 或 Xcode Command Line Tools，会生成适合当前 Mac 架构的 App；不需要另外安装 Python、Node 或第三方运行库。

测试覆盖模拟任务与额度、本机模拟服务、模拟语音授权与输入、合成启动会话；不打开 Codex 账号数据，不录音，也不向真实窗口输入文字。这些测试不能代替实体 Touch Bar、辅助功能或语音服务实测。

## 宠物、权限与隐私

王臭吉图片随项目按 MIT 许可发布。Codex 内置宠物素材不随包分发；选中内置宠物时回退为王臭吉。选中自定义云端宠物时，可从 Codex 本地缓存已有的图片地址加载；不会把这些图片写入仓库。

额度通过官方本机 `codex app-server` 读取，可能由该服务向 OpenAI 刷新账号信息。任务监控只读本地数据库中的任务 ID，接收本机 IPC 数据后只保留状态、待处理请求数和计时字段，不保存聊天正文。读取本机宠物选择时使用的账户标识也不会被打包或上传。加载自定义宠物会访问缓存中的 HTTPS 图片地址。

语音功能首次使用时需要麦克风和语音识别权限，文字输入还需要辅助功能权限。Apple 语音识别可能使用 Apple 服务，不保证离线。查看额度和宠物不需要麦克风权限。

语音不是向任意软件输入的全局听写：它会切回 Codex 宿主，优先当前宿主，其次独立 Codex，并核对可编辑焦点；不自动点击发送。无法确认窗口或首次授权尚未完成时，保留识别文字，选中目标文本框后再点“输入”。取消后迟到的授权或识别回调不会重新启动本次操作。

等待回应优先于工作中；观察到任务由进行中变为完成时才庆祝，旧完成任务和重连不会冒充新完成。它不会代你批准命令。

## 排查与卸载

Touch Bar 不显示：退出其他 Touch Bar 工具，确认 Codex 正在运行，点击顶部菜单的“重新加载 Touch Bar”。额度为 `--` 时检查 Codex 登录；宠物显示“未连接”时可能是桌面版本的私有接口发生变化，额度仍可能正常。

额度请求 20 秒未返回会结束等待，可再次刷新；后台失败后，手动刷新或正常的 60 秒定时刷新会尝试重连。刷新失败时保留旧数字，但 Touch Bar 会用橙色标出旧值及最后成功更新时间，菜单栏显示警告图标，悬停可看错误；成功更新后恢复正常。

退出本工具，然后运行：

```bash
launchctl bootout "gui/$(id -u)/com.github.csokiw.CodexTouchBarPet.Launcher"
```

把 App 和 `~/Library/LaunchAgents/com.github.csokiw.CodexTouchBarPet.Launcher.plist` 移到废纸篓；可一并清理 `~/Library/Application Support/CodexTouchBarPet/`。不要删除 `~/.codex`，那是 Codex 的登录和任务资料。

## 来源与许可

保留 Jack Chen、wjx8 的版权声明；本版本代码改动及王臭吉图片署名 CsokiW。详见 [LICENSE](LICENSE) 和 [第三方说明](THIRD_PARTY_NOTICES.md)。欢迎反馈和贡献，喜欢的话可以给这个仓库点个 Star。
