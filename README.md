# ChatGPT Proxy Launcher

**Codex 一直“重新连接（Reconnecting 1/5～5/5）”？代理已经开了，ChatGPT / Codex 还是连不上？**

给 Windows 桌面应用一个带代理、保留包身份的启动入口。

一个由 PowerShell 和 VBScript 组成的小工具。从桌面快捷方式启动应用，为本次进程设置本地代理，启动前检查代理端口，并在 Windows 应用包上下文中运行。无需安装 Node.js、Python 或额外依赖。

> 这是社区启动工具，与 OpenAI 无隶属关系。当前适配的是包名为 `OpenAI.Codex`、入口为 `app\ChatGPT.exe` 的 Windows 桌面应用。它不是代理服务器，也不提供代理节点。

## 为什么做这个

有时浏览器能联网、代理客户端也正常，桌面应用里的部分请求却依然失败。反复重装、切换配置，甚至关闭 WSL，都不一定找对原因。

本项目把几个容易遗漏的启动条件放到一个入口里：

| 遇到的痛点 | 启动器做什么 |
| --- | --- |
| Codex 反复“重新连接（Reconnecting 1/5～5/5）” | 针对代理未传入进程、启动环境不正确的场景，提供统一启动入口；使用者反馈改用后已恢复正常 |
| 已开启代理，应用或子进程仍未拿到代理设置 | 在启动链中设置 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`，供遵循这些变量的进程使用 |
| 为了带代理直接运行商店安装目录里的 EXE，缺少应用包上下文 | 使用 `Invoke-CommandInDesktopPackage` 创建带包身份的进程，启动前再次核验身份 |
| 代理没启动或端口填错，只看到应用连接失败 | 先检查本地 TCP 端口，连接失败时给出明确提示 |
| 每次启动都留着一个 PowerShell 窗口 | 使用 VBS 隐藏启动，不等待应用退出 |
| 应用升级后安装目录变了，旧快捷方式失效 | 每次通过当前用户的已安装包查找 EXE，不固定版本路径 |

### 实际使用中遇到的重连、WSL 和内置提示词问题

这个工具最初用于处理自己的 Windows 桌面使用问题：代理已经开启，但 **Codex 仍反复显示“重新连接（Reconnecting 1/5～5/5）”**；同时遇到过**卡在“结束 WSL”以及内置提示词加载异常**的现象。改用这个代理快捷方式后，这些现象在该使用环境中恢复正常。这是使用者反馈的案例。

这里把观察到的效果和代码能力分开说明：启动器直接处理的是**代理环境变量和 Windows 包身份**。它没有执行 `wsl --shutdown`，没有修改 WSL 配置，也没有读取、注入或修改内置提示词。因此，这个案例不代表已证明所有重连、WSL 或提示词问题都由同一原因引起，也不保证可以修复应用自身的缺陷。服务端故障、登录状态或不可用的代理节点等其他原因，仍需单独排查。

## 开启 WSL 有什么优势

WSL 是 Windows Subsystem for Linux，可以在 Windows 上同时使用 Linux 环境。对需要写代码、运行项目的人来说，它主要有这些价值：

- **直接使用 Linux 工具链**：运行 Bash、Linux 包管理器，以及面向 Linux 的 Node.js、Python、Go 等开发工具。
- **更贴近 Linux 服务器**：提前发现路径大小写、文件权限、Shell 脚本和依赖差异，减少本地能跑、部署后出问题的情况。
- **Windows 和 Linux 配合工作**：继续使用 Windows 桌面应用，同时在 Linux 环境里构建、测试和运行服务。
- **按项目选择环境**：依赖 Linux 的项目可以放在 WSL 中；Windows 原生项目继续在 Windows 中开发。

这些是 WSL 本身的能力，不是本启动器提供的新功能。仅使用桌面聊天或原生 Windows 工具时，不必为了这个启动器额外安装 WSL。可参考 [Microsoft 的 WSL 介绍](https://learn.microsoft.com/en-us/windows/wsl/about)。

**WSL 的网络需要单独核对。** 本工具设置的是 Windows 启动进程的环境，不会自动配置 Linux 内的代理。WSL 2 默认 NAT 模式下，Linux 中的 `127.0.0.1` 不能直接当作 Windows 的本地代理地址；受支持系统上的镜像网络模式可以让 WSL 通过 `127.0.0.1` 访问 Windows 服务。具体以 [Microsoft 的 WSL 网络说明](https://learn.microsoft.com/en-us/windows/wsl/networking)为准。

另外，WSL 和 WS / WebSocket 是两回事：前者是 Linux 开发环境，后者是网络通信协议。这个启动器既不会关闭 WSL，也不会强制关闭 WebSocket。

## 使用条件

- Windows 桌面系统，已为当前用户安装上述 `OpenAI.Codex` 应用包。
- 系统自带的 **Windows PowerShell 5.1**、Appx 模块及 Windows Script Host / VBScript 可用。运行下方的 `powershell.exe` 命令，不需要 PowerShell 7。
- 已有可用的本地 HTTP 或 mixed 代理，例如 FlClash 提供的 `127.0.0.1:7890`。SOCKS-only 端口不适用。
- 当前版本只支持 `127.0.0.1` 上的代理，可自定义端口；不处理代理认证。

安装目录位于当前用户目录。脚本不会主动请求管理员权限；如果系统策略禁用脚本宿主或阻止相关命令，应按组织策略处理。

## 安装和使用

### 下载即用（推荐）

1. 打开 [最新 Release](https://github.com/OrangeZh1/chatgpt-proxy-launcher/releases/latest)，下载附件 **chatgpt-proxy-launcher-windows-v1.0.0.zip**。这是整理好的安装包；GitHub 自动生成的 Source code 是源码包。
2. 右键 ZIP，选择“全部解压”，打开解压后的文件夹。
3. 先开启代理客户端，再双击 **Install.cmd**。安装器会自动读取 Windows 系统代理和代理环境变量，识别到可连接的本地代理后直接使用。无法识别时才提示输入端口，默认 `7890`。
4. 安装完成后，先开启代理，保存任务并完全退出 ChatGPT/Codex（包括托盘），再双击桌面 **ChatGPT Proxy**。

已有安装时会询问是否更新，确认后只替换启动器文件和快捷方式。包内 [QUICKSTART.txt](QUICKSTART.txt) 提供离线中文说明，Release 同时附带 SHA-256 校验值。

安装完成后，启动文件已复制到当前用户目录，可以删除下载的 ZIP 和解压目录。更换端口时重新运行安装入口并确认更新即可。

自动识别按“已启用的 Windows 系统代理 → `HTTPS_PROXY` → `HTTP_PROXY` → `ALL_PROXY`”顺序选择可连接的 `127.0.0.1` / `localhost` HTTP 代理，不扫描其他端口、不执行 PAC，也不接受带账号密码的地址。TCP 可连接不等于代理节点可用。端口在安装时保存到快捷方式中，不会每次启动都重新检测；需要固定端口时可使用下方 `-ProxyPort` 参数，手动值优先。

### 从源码安装

1. 下载此仓库的 ZIP 并解压，或克隆仓库：

   ```powershell
   git clone https://github.com/OrangeZh1/chatgpt-proxy-launcher.git
   cd chatgpt-proxy-launcher
   ```

2. 在解压后的项目目录打开 PowerShell，安装启动器：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
   ```

   脚本会把两个启动文件复制到 `%LOCALAPPDATA%\ChatGPTProxyLauncher`，并创建桌面快捷方式 **ChatGPT Proxy**。快捷方式使用系统 PowerShell 图标，仓库不分发 OpenAI 图标。命令中的执行策略参数仅作用于本次 PowerShell 进程，不会持久修改系统执行策略。

3. 启动代理客户端，确认 HTTP / mixed 端口已经开启。
4. 保存任务并完全退出现有 ChatGPT / Codex，包括托盘进程，再双击 **ChatGPT Proxy**。

启动器检测到目标应用仍在运行时会提示退出，不会强制结束任务。新的环境变量无法追加给已经运行的应用进程。

### 自定义代理端口

默认安装会尝试自动识别代理；无可用设置时使用 `7890`。例如需要固定为 `127.0.0.1:7897`，首次安装时运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -ProxyPort 7897
```

已有安装时，先检查安装目录是否有自己改过的脚本，再使用 `-Force` 更新：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -ProxyPort 7897 -Force
```

`-Force` 会替换安装目录里的两个同名启动脚本和目标桌面快捷方式，不清空目录。默认不覆盖已有文件。

### 不安装，直接运行

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-ChatGPT-With-Proxy.ps1 -ProxyPort 7890
```

直接运行便于排查；日常使用桌面快捷方式可以隐藏启动窗口。

## 只检查，不启动应用

在仓库目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-ChatGPT-With-Proxy.ps1 -CheckOnly -ProxyPort 7890
```

成功时输出 JSON，包含应用路径、是否正在运行、代理端口是否可达、期望/当前包身份及代理变量。失败时返回非零退出码。此模式不会启动或关闭应用，可以在当前会话运行时使用。

`proxy_reachable: true` 仅表示 **TCP 端口可连接**，不证明该端口提供正确的 HTTP 代理服务、节点可用或远端请求一定成功。外层检查的 `current_package` 也可能为空；真正启动时会在内层再次验证包身份。

诊断输出含本机路径，反馈问题前请去掉个人用户名等信息。不要提交账号令牌、聊天记录或完整应用配置。

## 工作原理与边界

```text
桌面快捷方式
  → VBS 隐藏启动 PowerShell
  → 检查应用包、代理端口和运行状态
  → 在目标 Windows 应用包上下文中启动内层 PowerShell
  → 核验包身份，设置代理环境变量
  → 启动 ChatGPT.exe
```

- 代理变量只在启动进程及继承其环境的子进程中设置，不写入用户/系统全局环境变量，也不修改系统代理。
- 设置 `NO_PROXY=localhost,127.0.0.1,::1`，让遵循该变量的本地请求绕过代理。
- 不修改应用安装文件、账号、提示词、模型提供方、WSL 或开机启动配置。
- 不接管所有流量。忽略代理环境变量的组件、已启动的后台服务以及 WSL 内的工具，可能需要各自配置。
- 保留 Windows 包身份通过 Microsoft 的调试命令实现。它不等同于官方启动入口的全部行为；Microsoft 对该命令的保证限于包身份及虚拟化资源访问，应用版本或系统策略变化仍可能影响兼容性。参见 [Invoke-CommandInDesktopPackage](https://learn.microsoft.com/en-us/powershell/module/appx/invoke-commandindesktoppackage?view=windowsserver2025-ps) 和 [GetCurrentPackageFullName](https://learn.microsoft.com/en-us/windows/win32/api/appmodel/nf-appmodel-getcurrentpackagefullname)。

## 常见问题

| 提示或现象 | 处理方法 |
| --- | --- |
| `Cannot connect to the proxy` | 启动代理客户端，核对 HTTP / mixed 端口；用 `-ProxyPort` 指定实际端口 |
| `ChatGPT is already running` | 保存工作并完全退出应用及托盘后重试 |
| `ChatGPT/Codex is not installed` | 确认当前用户安装的应用包名是否为 `OpenAI.Codex`；其他包名暂不支持 |
| 找不到 EXE、应用入口或包身份验证失败 | 应用包装结构可能变化；附上脱敏后的检查结果反馈，不要直接删除包身份校验 |
| 双击无反应 | 先运行 `-CheckOnly`；若检查通过，核对 Windows Script Host / VBScript 是否可用，或使用直接运行命令 |
| 仍卡在结束 WSL、提示词仍异常 | 本工具不修复 WSL 或提示词实现；记录具体报错，分别检查应用版本、WSL 状态和网络情况 |

卸载时删除桌面 **ChatGPT Proxy** 快捷方式，以及安装目录中的 `Start-ChatGPT-With-Proxy.ps1`、`Launch-ChatGPT.vbs`。只有确认目录为空时再删除目录，保留自己存放的其他文件。

## 本地验证

在已安装目标应用的 Windows 环境中，从源码仓库目录执行（Release 安装包不包含开发测试）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Launcher.ps1
```

检查脚本语法、端口参数、可达/不可达端口、代理变量、自动识别、临时安装、覆盖保护、双击安装入口和 VBS 参数传递。测试使用临时目录和本地测试端口，不需要外网代理，不启动或结束真实应用，也不调用 WSL。完整应用冷启动和服务端功能仍需在保存任务、退出应用后手动验证。

项目不配置自动触发的远端 CI。

## 许可证

[MIT](LICENSE)。许可证覆盖本仓库的启动脚本和文档，不授予 ChatGPT、Codex 或第三方商标的权利。
