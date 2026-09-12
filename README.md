# UI Control for Deepseek+Codex

**English** | [中文说明](#中文说明)

Give Codex **real, end-to-end control of Windows apps** - with or without the Computer Use plugin. Pure
PowerShell + P/Invoke, zero dependencies, works on the inbox Windows PowerShell 5.1 and on PowerShell 7. Built
and field-tested on **DeepSeek-V4.1** in Codex (native vision included); usable by every model Codex can run.

What it buys you is a **clean main session**: every capture is read out of band by a throw-away run - native
vision still does the seeing - and the picture is deleted the moment the read ends. No image bytes, no stale
screens, nothing left in memory to slow the next turn down or pull attention towards a window that has already
moved on.

```
selftest -> windows -> som/look -> steps -Do "activate|click:1001|type:hello|key:ENTER"
```

## Why it exists

The built-in Computer Use plugin (`@oai/sky`) is excellent - but it only exists where the app runtime ships it,
and every screenshot it takes stays in the conversation. A DeepSeek session in Codex gets no accessibility
bridge, no screenshots and no mouse; and any session that reads images pays for each capture again on every
later request, until the gateway refuses the body outright. This skill closes both gaps with a self-contained
engine a model drives through one CLI, and it fixes the failure mode that kills long GUI runs: **image
accumulation in the request body - and in the working memory**.

## Feature highlights

| Capability | What you get |
| --- | --- |
| **Real mouse & keyboard** | SendInput clicks, drags, wheel, chords, clipboard-typed text (IME-safe), Unicode mode |
| **API-level control** | `WM_COMMAND`, `BM_CLICK`, `WM_SETTEXT`, MSAA default actions, UI Automation invoke/select/set-value - no cursor, no focus change |
| **Element finding** | MSAA + UIA element trees, Set-of-Marks numbered screenshots (`som`), a marks table you can click by index, pixel-level analysis for apps with no accessibility tree |
| **Screenshots that never enter the conversation** | `shot` / `som` capture full resolution; `look` gets them read by a throw-away Codex run (native vision included), returns **text only**, and deletes the file the moment the read is over |
| **Context and memory stay flat** | No accumulated image bytes, no stale screens competing for attention, no request-body growth - a long run keeps the speed of a fresh one |
| **Occlusion rescue** | `reveal`: raise -> minimise blockers -> move blockers -> taskbar switch -> close session-created blockers -> Start Menu / desktop search |
| **Real desktop launching** | Double-click desktop icons like a human (DPI-aware enumeration + proven landing point), Start menu / UWP fallback |
| **Batch steps** | `steps -Do "activate|click:1001|type:...|key:ENTER|shot:out.png"` - one process, one round trip |
| **Hard safety gate** | Language-independent denylist (terminals, consoles, credential/security UI, password managers, the Codex window), landing-point proof before raw input, `-Force` only for user documents |
| **Two engines, one flow** | Switch between this engine and Computer Use per turn - never mixed inside one turn |

## Honest comparison with the native Computer Use plugin

| | **This skill** (`windows-ui-automation`) | **Computer Use plugin** (`@oai/sky`) |
| --- | --- | --- |
| Model support | Any model Codex runs; built and tuned on **DeepSeek-V4.1** - native vision is used, it just never enters the conversation | Requires a vision-capable model and the app runtime that ships the plugin |
| Install | Copy one folder into `%USERPROFILE%\.codex\skills\` - no config, no build, no packages | Bundled with the app; availability depends on your client/region |
| Dependencies | None (PowerShell 5.1 or 7 + P/Invoke, all inbox) | Ships with the app runtime |
| Screenshots | Full resolution, read **out of band** by a throw-away run of the same model (native vision does the reading); only text returns and the picture is deleted the moment the read ends | The harness hands images to the model and they stay in the conversation |
| Memory / context cost of a screenshot | A few hundred text tokens, **zero image bytes**, and the file is off the disk right after the read - nothing left to grow the request body | Image bytes stay in context, are re-sent every turn and are paid for again as input |
| Attention hygiene | The session holds only what still matters - no stale screen state competing with the window actually being driven | Every past screenshot stays in context and keeps shaping later steps |
| Long-run behaviour | Request body stays flat; `budget` shows live context size and pending shots | Depends on provider limits; large runs can hit body-size limits |
| Element finding | MSAA/UIA trees + numbered marks + pixel analysis (works with no accessibility tree at all) | Accessibility indices from the app |
| Input paths | Real input **and** message-level **and** UIA actions, chosen per case | Real input driven by the app |
| Occlusion handling | Built-in rescue chain, window-level control, taskbar/desktop search | Limited to what the app exposes |
| Batching / scripting | `steps` batches, action log, JSON output, drive it from any script or CI | Interactive, one action at a time |
| Safety | Hard, locale-independent denylist + landing-point proof + document guard | App-level policy |
| Platform | Windows only | Cross-platform where the app supports it |
| Best at | DeepSeek sessions, scripted/batch automation, pixel-exact verification, long autonomous runs, safety-gated input, apps with no accessibility tree | First-class in-app experience when a vision model is available |

Honest summary: when the plugin is available, its in-app flow is simpler - use it. Use this skill when you are on
DeepSeek (vision or not), when you need scripted/batch control, when the plugin is unavailable or times out, or
when the main conversation has to stay free of screenshots. The trade it makes is deliberate: **the model still
sees everything, the session remembers none of it.**

## Install (no extra steps)

1. Copy the `windows-ui-automation` folder into your Codex skills directory:

```powershell
# option A - git
git clone --depth 1 https://github.com/carolwjade/CarlopensourceBase "$env:TEMP\carlbase"
Copy-Item "$env:TEMP\carlbase\windows-ui-automation" "$env:USERPROFILE\.codex\skills\" -Recurse -Force

# option B - manual: download the repo ZIP, extract it, and copy the windows-ui-automation folder
#            into %USERPROFILE%\.codex\skills\
```

2. That is all. Codex discovers skills from `%USERPROFILE%\.codex\skills\` at the start of a thread - open a new
thread and the skill is live. No config edits, no installs, no build. (If your policy blocks scripts, call it as
`powershell -NoProfile -ExecutionPolicy Bypass -File <script>`.)

3. Optional sanity check:

```powershell
$ui = "$env:USERPROFILE\.codex\skills\windows-ui-automation\scripts\ui.ps1"
pwsh -File $ui selftest
```

## Quick start

```powershell
$ui = "$env:USERPROFILE\.codex\skills\windows-ui-automation\scripts\ui.ps1"
pwsh -File $ui decide -Task "rename a file in Explorer"      # should UI automation be used at all?
pwsh -File $ui windows -Visible                              # list windows -> note the Handle
pwsh -File $ui tree -Window <handle>                         # control tree with control IDs
pwsh -File $ui som -Window <handle> -Out "$env:TEMP\a.png"   # numbered screenshot + marks table (full res)
pwsh -File $ui look -Path "$env:TEMP\a.png" -Ask "where is the search box?"  # text back, image deleted
pwsh -File $ui somclick -Window <handle> -Index 3            # click mark 3 (-PreferAction: no mouse)
pwsh -File $ui steps -Window <handle> -Do "activate|click:1001|type:hello|key:ENTER"
pwsh -File $ui budget                                        # live context size + shots still on disk
```

From inside Codex you do not call these by hand - the skill tells the model when and how to use them.

## The problem it solves: screenshots that blow up the request

Every image a model reads is stored in the conversation and re-sent, byte for byte, on every later request. A
long GUI run on an image-reading model therefore grows the body until the gateway rejects it
(`413 Payload Too Large: Failed to buffer the request body: length limit exceeded`), and from that point every
later request fails - only a fresh thread can continue.

This engine never puts a capture into the conversation:

- `shot` / `som` always grab the **full-resolution** frame (never cropped, downscaled or re-encoded unless you
  ask with `-MaxWidth`) and print the exact read command.
- `look` hands the PNG to a throw-away Codex run (`--ephemeral`, persists no session) and brings back **text
  only**. A UI capture is never opened with `view_image`.
- The picture is deleted **the moment the read is over**, success or failure; `cleanup -Path` removes a shot
  whose answer came from somewhere else. Nothing is deleted by age, nothing is kept unless you say so - hold
  only what is still unread and re-shoot when needed.
- Text channels come first (`tree`, `marks -Json`, `uia text`, `msaa`, `list`), so many questions never need a
  picture at all.

## Safety model

- Every input - real **and** message-level - passes a locale-independent gate: terminals, consoles,
  security/credential dialogs, password managers and the Codex/ChatGPT windows are refused on any Windows UI
  language (process name, window class, loader command line, control-panel CLSID).
- Typing into an existing user document window requires `-Force`; `-Force` never unlocks the hard categories.
- Keys are checked against the focused window; raw coordinates are checked against the window that owns the
  point (an occluder is surfaced first, the intended target is raised and re-checked, and the click aborts
  instead of hitting whatever covers it).
- The engine only touches windows it launched or that you named; it never saves, deletes or sends anything on
  its own.

## Requirements and honest limits

- Windows 10/11, PowerShell 5.1 (inbox) or PowerShell 7 - nothing else.
- Chromium/Electron apps often publish no accessibility tree (`som` returns one element): fall back to a
  full-resolution screenshot, read the position, then real click/drag and read the screen back.
- Elevated (admin) windows cannot be driven from a non-elevated process.
- Windows only. Not a game/anti-cheat automation tool; do not use it against targets you are not allowed to
  automate.
- Coordinate work is real work: measure -> act -> read back, and re-measure after any state change.

## Field-tested

Developed and hardened on real end-to-end runs, including: launching a desktop client by double-clicking its
desktop icon, searching inside it, opening a video, locating a danmaku input by pixel-level analysis of a
full-resolution strip (the app exposes no accessibility tree), typing text, clicking send, and verifying the
result - with every capture read out of band and deleted immediately, so the request body never grew.

## Files

```
windows-ui-automation/
  SKILL.md                  skill definition (English; read by Codex)
  agents/openai.yaml        UI metadata
  scripts/uikit.ps1         engine: Win32 P/Invoke, MSAA/UIA, input, screenshots, safety, steps
  scripts/ui.ps1            CLI front end (run `ui.ps1 help` for the full command table)
  scripts/real-input.ps1    real mouse/keyboard batches
  scripts/drive-controls.ps1  message-level control (no cursor, no focus change)
  scripts/capture-window.ps1  window/monitor/region capture
  scripts/list-windows.ps1    window and control-tree listing
  scripts/desktop-launch.ps1  human-style desktop-icon launching with a verified landing point
```

## Keywords

windows-ui-automation, Codex skill, DeepSeek, Codex, computer-use alternative, UI automation, GUI automation,
RPA, desktop automation, PowerShell, P/Invoke, Win32, MSAA, UI Automation, UIA, accessibility, SendInput, real
mouse, real keyboard, screenshot, Set-of-Marks, OCR-free, AI agent, LLM agent, autonomous agent, occlusion
rescue, safety gate, image-free context, context hygiene, attention hygiene, memory efficiency, payload too
large, 413, context engineering.

---

## 中文说明

**给 Codex 装上真正的 Windows UI 操作能力** —— 有没有 Computer Use 插件都能用。纯 PowerShell + P/Invoke 实现，
零依赖零安装，Windows 自带的 PowerShell 5.1 和 PowerShell 7 都能跑；以 Codex 里的 **DeepSeek-V4.1** 为主力调试，
原生视觉照常使用，也能被任何 Codex 模型使用。

它换来的是**一个干净的主会话**：每次截图都交给一次性进程离线读取（看图仍然用模型自己的原生视觉），读完立刻删除
图片；既不占图片字节、不留过期画面，也不给后续步骤留下干扰注意力的旧状态。

### 为什么需要它

原生 Computer Use 插件（`@oai/sky`）很优秀，但它只在随应用分发它的地方存在，而且它拍的每张截图都会留在对话里。
Codex 里的 DeepSeek 会话拿不到元素树、截图和鼠标；而任何会读图的会话，每张截图都会在之后每一次请求里被重复
发送，直到网关直接拒收请求体。本技能用一个自包含引擎同时补上这两块短板，并顺手解决了长时 UI 任务的致命伤：
**请求体和工作记忆被截图撑爆**。

### 能力亮点

- **真实键鼠**：SendInput 点击、拖拽、滚轮、组合键、剪贴板输入（绕开输入法干扰）、Unicode 模式。
- **消息级/API 级控制**：`WM_COMMAND`、`BM_CLICK`、`WM_SETTEXT`、MSAA 默认动作、UIA invoke/select/set-value，
  不动鼠标、不抢焦点。
- **元素定位**：MSAA + UIA 元素树、Set-of-Marks 编号截图、可按序号点击的元素表，以及为"没有无障碍树"的应用
  准备的像素级分析。
- **截图永不进上下文**：`shot`/`som` 全分辨率抓取；`look` 交给一次性 Codex 进程读取（原生视觉照常发挥），
  **只回文本**，读完立刻删除图片（成功失败都删）。
- **省内存、省上下文**：不累积图片字节、不留过期画面干扰注意力、请求体不增长——长任务也能保持接近新会话的速度。
- **遮挡自救**：置前 → 最小化遮挡 → 挪开遮挡 → 任务栏切换 → 关闭本会话新建的遮挡 → 开始菜单/桌面搜索。
- **像人一样启动**：真实双击桌面图标（DPI 感知枚举 + 落点校验），失败才回退开始菜单/UWP 搜索。
- **批量步骤**：`steps -Do "activate|click:1001|type:...|key:ENTER|shot:out.png"`，一个进程一次往返。
- **硬性安全闸**：与系统语言无关的禁用名单（终端、控制台、安全/凭据界面、密码管理器、Codex 窗口），原始输入
  前先验证落点，仅对"用户文档窗口"可用 `-Force` 解禁。
- **两套引擎可切换**：与本机原生 Computer Use 按轮次切换，同一轮内绝不混用。

### 与原生 Computer Use 插件的诚实对比

| | **本技能**（windows-ui-automation） | **Computer Use 插件**（@oai/sky） |
| --- | --- | --- |
| 模型支持 | 任何 Codex 模型；以 **DeepSeek-V4.1** 为主力调试——原生视觉照常使用，只是图片不进入对话 | 需要具备视觉能力的模型与随应用分发的运行时 |
| 安装 | 把一个文件夹复制进 `%USERPROFILE%\.codex\skills\`，无需配置/编译/装包 | 随应用附带，能否使用取决于客户端与地区 |
| 依赖 | 无（PowerShell 5.1/7 + P/Invoke，全部系统自带） | 依赖应用运行时 |
| 截图处理 | 全分辨率抓取，由同一模型的一次性进程**离线读取**，只回文本、读完即删 | 由宿主把图片交给模型，图片留在对话中 |
| 截图的内存/上下文代价 | 仅几百个文本 token，**零图片字节**，磁盘文件读完即删，请求体不增长 | 图片字节留在上下文，每次请求重发并重复计入输入 |
| 注意力卫生 | 会话只保留仍然有效的信息，过期画面不会和当前窗口争夺注意力 | 历史截图长期留在上下文，持续影响后续判断 |
| 长时运行 | 请求体保持平稳，`budget` 可随时查看上下文与待处理截图 | 受服务商体积上限影响，长任务可能触及上限 |
| 元素定位 | MSAA/UIA 元素树 + 编号标记 + 像素分析（完全没有无障碍树也能干） | 应用提供的无障碍下标 |
| 输入方式 | 真实输入 / 消息级 / UIA 动作，按场景择优 | 由应用驱动的真实输入 |
| 遮挡处理 | 内置自救链 + 窗口级控制 + 任务栏/桌面搜索 | 取决于应用 |
| 批处理与脚本化 | `steps` 批处理、动作日志、JSON 输出，可被任何脚本或 CI 调用 | 交互式，一次一个动作 |
| 安全 | 与语言无关的硬性名单 + 落点校验 + 文档保护 | 应用级策略 |
| 平台 | 仅 Windows | 应用支持的各平台 |
| 最擅长 | DeepSeek 会话、脚本化/批处理、像素级验证、长时自主运行、需要安全闸的输入、没有无障碍树的应用 | 有视觉模型时的第一优先体验 |

诚实结论：插件可用时它的应用内流程更简单，**优先用它**；当你用 DeepSeek（有无原生视觉都一样）、需要脚本化/
批处理、插件不可用或超时、或者主会话必须保持无截图时，用本技能。它的取舍很明确：**模型照样看得见，会话什么都
不记。**

### 安装（复制即生效）

1. 把 `windows-ui-automation` 文件夹复制到 Codex 技能目录：

```powershell
# 方式 A - git
git clone --depth 1 https://github.com/carolwjade/CarlopensourceBase "$env:TEMP\carlbase"
Copy-Item "$env:TEMP\carlbase\windows-ui-automation" "$env:USERPROFILE\.codex\skills\" -Recurse -Force

# 方式 B - 手动：下载仓库 ZIP、解压，把 windows-ui-automation 文件夹复制进 %USERPROFILE%\.codex\skills\
```

2. 到此为止。Codex 在线程启动时自动发现 `%USERPROFILE%\.codex\skills\` 下的技能——新开一个线程即可使用，
   无需改配置、无需安装、无需编译。（若系统策略禁止运行脚本，用
   `powershell -NoProfile -ExecutionPolicy Bypass -File <脚本>` 调用。）

3. 可选自检：

```powershell
$ui = "$env:USERPROFILE\.codex\skills\windows-ui-automation\scripts\ui.ps1"
pwsh -File $ui selftest
```

### 快速上手

```powershell
$ui = "$env:USERPROFILE\.codex\skills\windows-ui-automation\scripts\ui.ps1"
pwsh -File $ui decide -Task "在资源管理器里重命名一个文件"   # 先判断该不该用 UI
pwsh -File $ui windows -Visible                              # 列出窗口，记下 Handle
pwsh -File $ui tree -Window <handle>                         # 控件树（含控件 ID）
pwsh -File $ui som -Window <handle> -Out "$env:TEMP\a.png"   # 编号截图 + 元素表（全分辨率）
pwsh -File $ui look -Path "$env:TEMP\a.png" -Ask "搜索框在哪？"   # 只回文本，图片随即删除
pwsh -File $ui somclick -Window <handle> -Index 3            # 点击 3 号标记（-PreferAction 不动鼠标）
pwsh -File $ui steps -Window <handle> -Do "activate|click:1001|type:你好|key:ENTER"
pwsh -File $ui budget                                        # 查看上下文体积与待处理截图
```

在 Codex 里不需要你手敲这些命令——技能会告诉模型什么时候用、怎么用。

### 它解决的核心问题：截图撑爆请求体、污染上下文

模型读过的每张图片都会留在对话里，并在之后的每次请求中**逐字节重发**。长时 UI 任务会让请求体持续膨胀，直到网关
拒收（`413 Payload Too Large: Failed to buffer the request body: length limit exceeded`），此后每次请求都会
失败，只能开新线程续跑。

本引擎的截图永远不进对话：`shot`/`som` 全分辨率抓取并给出读取命令；`look` 用一次性 Codex 进程读取，只带回
**文本**，图片在读取结束的瞬间删除；`cleanup -Path` 清理"答案已由其他渠道得到"的截图；不按时间删，只保留尚未读
取的画面，需要时重新截取即可。文本通道优先（`tree`、`marks -Json`、`uia text`、`msaa`、`list`），很多问题根本
不需要图片。

省下来的不只是字节：会话里没有过期画面，模型每一步都只面对"当前真实窗口 + 仍然有效的信息"，注意力不被旧状态
牵着走，长任务的速度和判断力都更接近刚开始的时候。

### 安全模型

- 所有输入（真实输入**与**消息级输入）都要过与系统语言无关的安全闸：终端、控制台、安全/凭据对话框、密码管理
  器、Codex/ChatGPT 窗口一律拒绝（按进程名、窗口类、加载器命令行、控制面板 CLSID 判断）。
- 向"已存在的用户文档窗口"输入需要 `-Force`，且 `-Force` 永远不会解锁上面那些硬禁类别。
- 按键前校验焦点窗口，原始坐标点击前校验落点所属窗口：被遮挡时先置前目标并复验，仍不安全就中止，绝不盲点。
- 只操作自己启动或你明确指定的窗口；不代替你保存、删除或发送任何东西。

### 环境要求与边界

- Windows 10/11 + 系统自带 PowerShell 5.1 或 PowerShell 7，别无其他依赖。
- Chromium/Electron 应用常常不提供无障碍树（`som` 只返回一个元素）：此时用全分辨率截图 + 像素定位 + 真实点击，
  再读屏复核。
- 提权（管理员）窗口无法从非提权进程驱动。
- 仅支持 Windows；不是游戏/反作弊自动化工具，请勿用于你无权自动化的目标。
- 坐标定位是"实打实"的活：测量 → 操作 → 回读，任何状态变化后重新测量。

### 实战验证

本技能在真实端到端任务中打磨：双击桌面图标启动桌面客户端 → 应用内搜索 → 打开视频 → 在应用完全没有无障碍树的
情况下用像素级分析定位弹幕输入框 → 输入文本 → 点击发送 → 复核结果；全程截图都走离线文本读取并即时删除，请求体
始终没有增长。

### 文件结构

```
windows-ui-automation/
  SKILL.md                  技能定义（英文，Codex 读取）
  agents/openai.yaml        UI 元数据
  scripts/uikit.ps1         引擎：Win32 P/Invoke、MSAA/UIA、输入、截图、安全闸、批处理
  scripts/ui.ps1            命令行前端（`ui.ps1 help` 查看完整命令表）
  scripts/real-input.ps1    真实键鼠批处理
  scripts/drive-controls.ps1  消息级控制（不动鼠标、不抢焦点）
  scripts/capture-window.ps1  窗口/显示器/区域截图
  scripts/list-windows.ps1    窗口与控件树列表
  scripts/desktop-launch.ps1  拟人化桌面图标启动（落点校验）
```

### 关键词

Windows UI 自动化、Codex 技能、DeepSeek、Codex、Computer Use 替代方案、GUI 自动化、RPA、桌面自动化、PowerShell、
P/Invoke、Win32、MSAA、UI Automation、无障碍、SendInput、真实键鼠、截图、Set-of-Marks、免 OCR、AI Agent、
智能体、长时自主运行、遮挡自救、安全闸、上下文卫生、注意力卫生、省内存、请求体超限、413、上下文工程。

## License

MIT - see [LICENSE](LICENSE).
