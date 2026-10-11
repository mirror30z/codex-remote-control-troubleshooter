# Codex Remote Control 无法启用：Windows 排查 Skill

**English:** A Codex skill for “Unable to enable Remote Control” on Windows. It distinguishes a working explicit proxy with broken direct traffic, proxy/TUN bypass, Clash Fake-IP route collisions, and account or workspace pairing issues.

在 Windows 版 ChatGPT/Codex Desktop 点击“允许”后，若出现 **“无法启用远程控制。请重试”**，可以安装这个 Codex skill，让 Codex先收集只读诊断信息，再根据实际结果选择修复方法。

本仓库针对两类已观察到的网络故障：

| 情况 | 可观察证据 | 处理方向 |
| --- | --- | --- |
| 系统代理可用，但后台连接没有正确经过代理 | 直连远程端点失败，显式代理迅速收到 HTTP 响应；代理软件的 TUN 模式关闭 | 启用正在使用的代理软件的 TUN／全设备模式，或修正分流规则，再重试远程控制 |
| Clash/Mihomo Fake-IP 与 VPN 虚拟网段冲突 | DNS 返回 Fake-IP，`Find-NetRoute` 选择了不该处理它的 VPN 网卡 | 先查清冲突网段，再暂停冲突 VPN 或调整 Fake-IP 地址池 |

第一类是本仓库作者机器上的实际修复：当时 0dcloud 的系统代理能访问远程端点，但直连被重置；开启 0dcloud 的虚拟网卡模式（TUN）后，直连探测收到 HTTP 426，手机控制 Codex 也成功。第二类是 [谢文峰的 Clash TUN 与 aTrust 排查文章](https://juejin.cn/post/7661898272260964378)描述的另一种故障。两种情况不能仅凭相同的弹窗文字混为一谈。

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

## 能解决到什么程度

安装 skill 会让 Codex知道如何定位这类故障，并在证据充分时执行或指导对应修复。它不能保证所有远程控制失败都来自网络，也不能替用户完成账号验证、工作区管理员授权或手机扫码。最终以桌面端出现配对码、手机连接成功并完成一次实际操作为准。

电脑端需要保持运行、联网且不休眠。配对、账号和工作区要求见 [OpenAI Remote connections 官方文档](https://learn.chatgpt.com/docs/remote-connections)。

**English search terms:** ChatGPT Codex Remote Control cannot enable on Windows, unable to enable remote control, Codex mobile pairing, WebSocket ECONNRESET, HTTP 403, proxy TUN, Clash Fake-IP, aTrust route conflict.

## 许可

本项目采用 MIT License。排查步骤由本仓库独立编写；所链接的第三方文章版权归原作者所有。
