# Codex Remote Control 无法启用：Windows 排查 Skill

支持 Windows PowerShell 5.1 / PowerShell 7。先确认桌面端设置、登录状态、版本和休眠，再按证据排查网络；每次修复保留原值与回滚方法。

**English:** A Codex skill for Windows Remote Control setup, availability, and phone-offline failures. It separates proxy/TUN bypass, DNS and IPv6 paths, Fake-IP route collisions, WebSocket or Cloudflare challenges, and account or workspace pairing issues.

在 Windows 版 ChatGPT/Codex Desktop 点击“允许”后，若出现 **“无法启用远程控制。请重试”**，可以安装这个 Codex skill，让 Codex 先收集只读诊断信息，再根据实际结果选择修复方法。

## 问题现象

桌面端能够打开“允许你的设备控制这台电脑？”弹窗，但点击“允许”后显示红色报错，无法进入手机扫码配对步骤：

![Windows 桌面端点击“允许”后提示“无法启用远程控制。请重试”](assets/remote-control-enable-error.png)

相同的提示可能由不同故障引起。仅凭这张截图，不能判断是账号权限、代理、TUN，还是虚拟网卡路由的问题。

## 可能出现的故障分支

远程控制失败可能对应不同的故障。Skill 会先收集当前机器的证据，再选择分支：

| 情况 | 可观察证据 | 处理方向 |
| --- | --- | --- |
| 系统代理可用，但后台连接没有正确经过代理 | 直连远程端点失败，显式代理迅速收到 HTTP 响应；代理软件的 TUN 模式关闭 | 启用正在使用的代理软件的 TUN／全设备模式，或修正分流规则，再重试远程控制 |
| Clash/Mihomo Fake-IP 与 VPN 虚拟网段冲突 | DNS 返回 Fake-IP，`Find-NetRoute` 选择了不该处理它的 VPN 网卡 | 先查清冲突网段，再暂停冲突 VPN 或调整 Fake-IP 地址池 |
| DNS 未走预期的代理解析路径 | Windows 默认 DNS 与已确认的代理 DNS 返回不同结果，或 IPv6 走了另一条路径 | 核对代理 DNS 模式和当前网卡配置，仅修正有证据的设置 |
| 代理能收到 HTTP 响应，但桌面远程控制仍失败 | 最近的应用日志显示 WebSocket 超时；或响应带 `Cf-Mitigated: challenge` | 检查应用进程实际代理路径、代理节点和挑战响应；必要时考虑只影响 Codex 的代理启动方式 |
| 电脑进程运行，手机仍显示离线 | 只有本地进程或启动器存活，没有当前手机连接的证据 | 分开核对桌面状态、手机账号、休眠、云端连接和近期日志 |

### 系统代理可用，TUN 未接管后台连接

在本仓库对应的实际故障中，0dcloud 的系统代理可以访问远程控制端点，但直连连接被重置。检查时 0dcloud 已连接、系统代理已开启，虚拟网卡模式（TUN）却是关闭的。开启 TUN 后，直连探测收到了 HTTP 426，桌面端成功启用远程控制，手机也完成了实际连接。

HTTP 426 只说明普通 HTTP 探测到达了端点，并不等于 WebSocket 配对成功；这里的最终依据是手机实际连上了电脑。

### Clash Fake-IP 被 aTrust 路由截走

另一类案例中，Clash/Mihomo 把 `chatgpt.com` 解析为 `198.18.0.12` 一类的 Fake-IP，地址池使用 `198.18.0.0/16`。同一台 Windows 电脑上的 Sangfor aTrust 虚拟网卡也建立了指向 `198.18.0.0/16` 的路由。Windows 对这个目标地址选择了 aTrust 网卡，请求因此未能按预期进入 Clash TUN，远程控制连接持续超时。显式指定 Clash 代理端口时却能收到 HTTP 响应，帮助将故障缩小到本机 DNS、TUN 和路由路径。

这一类问题要先用 `Resolve-DnsName chatgpt.com` 查看当前解析结果，再用 `Find-NetRoute -RemoteIPAddress <实际返回的 IP>` 核对选中的网卡。确认冲突后，可以在不需要公司 VPN 时暂时停用它，或把 Clash 的 Fake-IP 地址池改到**本机确认未被占用**的网段，并重新加载 TUN、刷新 DNS。`198.19.0.1/16` 只是某台机器上的可用例子，不能直接套用。修改后仍需回到桌面端和手机端验证。

### 其他情况怎样判别

诊断脚本现在会同时查看 `chatgpt.com` 的 IPv4/IPv6 解析、当前网卡的 DNS 服务器、本地代理端口是否在监听、Codex/ChatGPT 进程到当前解析地址的连接，以及远程控制端点的直连与显式代理结果。已知代理 DNS 服务器时，可用 `-DnsServer <地址>` 比较；系统代理无法识别时，可用 `-ProxyUrl <代理 URL>` 指定测试端口。这两个参数都不是固定配置值。

如果 HTTP 返回 `403`，还需区分一般状态码与 `Cf-Mitigated: challenge`。普通 `curl` 探测即使得到响应，也不能证明已登录的 WebSocket 或手机连接成功。进程正在运行同样只说明本地状态，不能证明手机能看到电脑。Skill 会在这些情况下结合当前应用状态和近期错误继续排查。

当 TUN 与其他网络需求冲突时，可以研究**仅让 Codex 进程使用代理**的启动方式；是否有效取决于实际安装版本、进程是否继承代理配置，以及代理是否支持 WebSocket。不会默认改写系统路由、代理或任务历史。

## 安装

在 Codex 中发送：

```text
$skill-installer 安装 https://github.com/mirror30z/codex-remote-control-troubleshooter/tree/main/skills/codex-remote-control-fix
```

安装后，在新对话中发送：

```text
$codex-remote-control-fix 帮我排查 Windows 上“无法启用远程控制。请重试”。
```

也可以手动把 [`skills/codex-remote-control-fix`](skills/codex-remote-control-fix) 文件夹复制到 `~/.codex/skills/`。Skill 包含可选的只读 PowerShell 诊断脚本；它不会自动修改 VPN、路由、防火墙或代理设置。

在发生故障的 Windows 电脑上，用普通权限的 PowerShell 运行诊断脚本。不要在 WSL 或云端容器中代替这台电脑采集：

```powershell
& ".\skills\codex-remote-control-fix\scripts\diagnose.ps1"
```

跳过端点 HTTP 探测，只收集本机状态和 DNS 查询结果：

```powershell
& ".\skills\codex-remote-control-fix\scripts\diagnose.ps1" -SkipProbes
```

脚本会读取 DNS、路由、代理配置及进程状态，并默认发送不带登录凭据的 HTTP 探测；不会读取应用令牌或修改网络。JSON 报告仍可能包含内网地址、网卡名称等信息，公开前应脱敏。权限不足或缺少命令会留下错误字段，不能当成“没有问题”。系统 PAC 不会被自动求值，需要确认实际代理后再指定 `-ProxyUrl`；参数不接受带账号密码的 URL。

默认探测路径是观察到的内部端点，并非稳定公开 API。遇到 `404` / `410`，应结合当前应用日志确认路径后，再用 `-Endpoint` 指定不含凭据或查询参数的 HTTPS URL。所谓直连是“不显式使用代理”，仍可能经过已开启的 TUN / VPN。

若已从代理软件确认其 DNS 监听地址，可追加 `-DnsServer <地址>`；若需指定显式代理，可追加 `-ProxyUrl http://127.0.0.1:<端口>`。不要把示例端口用于未确认的代理。

## 能解决到什么程度

安装 skill 会让 Codex 知道如何定位这类故障，并在证据充分时执行或指导对应修复。它不能保证所有远程控制失败都来自网络，也不能替用户完成账号验证、工作区管理员授权或手机扫码。最终以桌面端出现配对码、手机连接成功并完成一次实际操作为准。

电脑端需要保持运行、联网且不休眠。配对、账号和工作区要求见 [OpenAI Remote connections 官方文档](https://learn.chatgpt.com/docs/remote-connections)。

官方文档还说明：退出登录会关闭 Remote Control，但保留配对；重新登录后需再次开启。移动端配对从桌面应用开始，不能从 CLI / IDE 直接设置。遇到开启后选择 Add 的报错，可先保存当前工作，再重启桌面应用重试。产品入口名称可能随版本变化，以当前官方文档和应用界面为准。

## 验证与维护

仓库的 GitHub Actions 在 Windows PowerShell 5.1 和 PowerShell 7 下验证脚本语法、代理解析、探测参数隔离、挑战响应、错误脱敏、本地端口检测和 JSON 输出。测试不会尝试登录或配对。

```powershell
& ".\tests\diagnose.Tests.ps1"
```

这些测试验证诊断脚本；真实恢复仍需桌面端启用成功、手机显示在线，并从手机完成一次实际操作。反馈故障时，请提供版本、错误原文及时间、当前代理/VPN 模式和脱敏后的关键字段。

**English search terms:** ChatGPT Codex Remote Control cannot enable on Windows, unable to update remote control availability, Codex mobile host offline, mobile pairing, WebSocket timeout, Cloudflare Cf-Mitigated challenge, DNS leak, IPv6, proxy TUN, Clash Fake-IP, aTrust route conflict.

## 相关项目

扩展排查范围时参考了 [codex-remote-network-diagnostics](https://github.com/c1553011073-byte/codex-remote-network-diagnostics) 的 DNS 和进程路由检查、[Codex-Connectivity](https://github.com/zhenyangLab/Codex-Connectivity) 的进程级代理与 WebSocket 场景，以及 [codex-remote-mobile-debug-skill](https://github.com/VV-520/codex-remote-mobile-debug-skill) 的手机离线与 Cloudflare 挑战分层判断。本仓库的说明、脚本和操作步骤独立编写；不会将任何项目的固定网段、端口或启动方式当作通用解法。

## 许可

本项目采用 MIT License。说明和排查步骤由本仓库独立编写，不转载第三方文章。
