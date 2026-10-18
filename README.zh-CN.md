[English](README.md) | **中文** | [Español](README.es.md) | [Português](README.pt-BR.md)

# MSI Center：修复 "Read data of PSU GET_ALL fail"

如果你用的是带 USB 监控功能的微星电源（比如 **MEG Ai1300P**）并安装了 MSI Center，那么它的 Power Supply Unit 日志里很可能刷满了这样的行：

```
10-18-2026 21:50:01.933 | [ERROR] Read data of PSU GET_ALL fail... (6)
```

这类报错每分钟出现 3–5 次，一天大约 5000 条。**你的电源和 USB 都没有问题。** 错误来自 MSI Center 自身的一个 bug，本仓库提供对应的补丁。

## 问题出在哪

MSI Center 每秒会向电源请求一次全部读数（命令 `0xE0`，GET_ALL）。返回的是一组 PMBus LINEAR11 格式的数值：+12V、各路电流、+5V、+3.3V 等等。

模块里校验回复的函数（`API_Power Supply Unit.dll` 1.0.0.38 中的 `cPSU.Get`）只要发现第 3 字节为 `0xFE`，就把这条回复当作错误。这条规则对所有命令通用，但对 GET_ALL 来说，第 3 字节恰好是 **+12V 读数**的低字节。当电源上报的数值正好是 **11.969 V**（`0xD2FE`）时，MSI 就会把一条完全有效的回复丢掉，然后不加间隔地连续重试 6 次，每次拿到的电压都一样，最后记一条 `GET_ALL fail`。括号里的数字只是失败计数器，并不是错误码。

所以报错多不多，取决于你的 +12V 是否刚好停在 11.969 V 上，和 USB、线材、AIDA64/HWiNFO/iCUE 或负载都没有关系。详细分析和证据见：[docs/technical.md](docs/technical.md)（英文）。

## 我中招了吗？

在 PowerShell 中运行（不需要管理员权限）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check-log.ps1
```

它会按小时统计今天日志里的 `GET_ALL fail` 行数。

## 补丁做了什么

它在 `cPSU.Get` 中插入 3 条 IL 指令：`if (cmd == 0xE0) 跳过 0xFE 检查`。模块的其他部分一概不动，其他命令仍然使用原来的检查。

在 MEG Ai1300P 上实测 10 分钟的结果：

| | 日志中的错误数 | GET_ALL 请求数 | 被接受的 +12V = 11.969 V 的回复 |
|---|---|---|---|
| 原版 | 36 | 1199 | 0 |
| 打补丁后 | **0** | **594**（每秒一次） | **67 / 67** |

实际效果：
- 日志干净了；
- 不再丢失几秒钟的读数；
- 电源不会再被连续 6 次重试轰炸。

电源本身的行为完全不受影响，单路/多路 12V 模式、OCP 和风扇设置都不会被改动。

**本仓库不包含任何 MSI 的文件。** 补丁程序会读取*你自己*已安装的 DLL，校验其 SHA-256，然后只对副本打补丁。

## 最省事的办法：交给 AI 智能体

如果你在用 AI 编程智能体（Claude Code、Codex、Cursor、Copilot 的 agent 模式等），在其中打开本仓库的文件夹，然后粘贴下面这段话：

```
请阅读本文件夹中的 AGENTS.md 并按其步骤操作：检查我的电脑是否受 MSI Center "GET_ALL fail" bug 影响，如果受影响就应用修复。每一步会修改我系统的操作都要先问我。
```

[AGENTS.md](AGENTS.md) 会带着智能体安全地走完整个流程：
- 检查日志；
- 校验模块哈希，遇到不支持的版本直接拒绝；
- 必要时安装 .NET SDK；
- 说明将要改动的内容，并在执行前征求你的同意；
- 运行安装脚本；
- 验证结果。

## 下载

在本页点击 **Code → Download ZIP**，解压到任意位置即可。也可以用 `git clone https://github.com/lostintired/msi-psu-getall-fix`。

## 环境要求

- Windows 10/11，已安装带 Power Supply Unit 组件的 MSI Center，模块版本为 **1.0.0.38**。其他版本会被拒绝，不会做任何改动。
- [.NET 10 SDK](https://dotnet.microsoft.com/download)，用于编译补丁程序。
- 管理员权限。

## 安装

在**管理员** PowerShell 中，于仓库文件夹下运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

脚本会依次执行：
1. 检查模块是否为原版 1.0.0.38（SHA-256 `F7833895…0274BB`）；
2. 把它复制到 `C:\Program Files\MsiPsuGetAllFix\` 作为备份；
3. 编译补丁程序，对副本打补丁，并校验结果（SHA-256 `6535FEB9…5D2B46`；补丁结果是确定的）；
4. 替换原模块并重启 `MSI_Center_Service`。MSI Center 会重新加载所有组件，需要几秒钟；
5. 注册计划任务 **"MSI PSU GET_ALL fix guard"**，在登录时和每天各运行一次：
   - 如果 MSI Center 更新把原版 1.0.0.38 还原回来了，就重新打补丁；
   - 如果出现了*其他*版本，则不做任何改动，只弹出通知。可能是 MSI 已经修复了这个 bug，也可能是补丁程序需要更新。

加上 `-NoGuard` 可以跳过计划任务；如果 MSI Center 不在默认路径下，用 `-MsiCenterDir "D:\...\MSI Center"` 指定位置。

安装后验证：等几分钟再运行 `scripts\check-log.ps1`，安装时间点之后不应再出现新的报错行。

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\MsiPsuGetAllFix\uninstall.ps1"
```

它会还原原版模块、重启服务，并删除计划任务和安装文件夹。

## 注意事项

- 打过补丁的 DLL 上，MSI 的 Authenticode 签名不再有效。MSI Center 不会检查这个签名（它通过 `Assembly.LoadFile` 加载组件），但杀毒软件可能会报警。
- 仅支持模块 1.0.0.38。以后 MSI 的更新可能会修掉这个 bug，也可能改动代码。无论哪种情况，守护任务都不会去动新模块。
- 只在一台机器上测试过：MEG Ai1300P（USB `VID_0DB0&PID_56D4`）、MSI Center 2.0.74.0、SDK 3.2026.0911.01。同一段代码路径还服务另外两款电源型号（产品 ID 为 59209 和 51691）。欢迎其他型号的用户反馈情况。
- 风险自负。本项目与 MSI 无任何关联。这个 bug 已经向 MSI 技术支持反馈过。

## 许可证

本仓库中的代码采用 MIT 许可证。MSI Center 及其组件归 MSI 所有。
