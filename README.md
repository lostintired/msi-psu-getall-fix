[English](README.md) | [中文](README.zh-CN.md) | [Español](README.es.md) | [Português](README.pt-BR.md)

# MSI Center: fix for "Read data of PSU GET_ALL fail"

If you have an MSI PSU with USB monitoring (found on a **MEG Ai1300P**) and MSI Center, its Power Supply Unit log is probably full of lines like this:

```
10-18-2026 21:50:01.933 | [ERROR] Read data of PSU GET_ALL fail... (6)
```

They appear 3–5 times a minute, around 5,000 a day. **Your PSU and your USB are fine.** The error comes from a bug in MSI Center itself, and this repo patches it.

## What's wrong

Once a second MSI Center asks the PSU for all its readings (command `0xE0`, GET_ALL). The reply is a list of PMBus LINEAR11 values: +12V, the per-rail currents, +5V, +3.3V and so on.

The module's reply check (`cPSU.Get` in `API_Power Supply Unit.dll` 1.0.0.38) treats a reply as an error whenever byte 3 is `0xFE`. That rule is shared by all commands. For GET_ALL, though, byte 3 is the low byte of the **+12V reading**. When the PSU reports exactly **11.969 V** (`0xD2FE`), MSI throws a valid reply away. It retries 6 times in a row with no pause, gets the same voltage each time, and logs `GET_ALL fail`. The number in brackets is a running failure counter, not an error code.

So the error rate depends on whether your +12V happens to sit at 11.969 V. It has nothing to do with USB, cables, AIDA64/HWiNFO/iCUE or load. Details and evidence: [docs/technical.md](docs/technical.md).

## Am I affected?

Run this in PowerShell (no admin needed):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check-log.ps1
```

It counts `GET_ALL fail` lines per hour in today's log.

## What the patch does

It inserts 3 IL instructions into `cPSU.Get`: `if (cmd == 0xE0) skip the 0xFE check`. Nothing else in the module changes, and other commands keep the original check.

Measured on a MEG Ai1300P over 10 minutes:

| | errors in log | GET_ALL requests | replies with +12V = 11.969 V accepted |
|---|---|---|---|
| original | 36 | 1199 | 0 |
| patched | **0** | **594** (one per second) | **67 / 67** |

In practice:
- the log is clean;
- no seconds of readings are dropped;
- the PSU no longer gets bursts of 6 retries.

PSU behaviour is untouched. Rail mode, OCP and fan settings are not affected.

**This repo contains no MSI files.** The patcher takes *your own* installed DLL, checks its SHA-256, and patches a copy.

## Easiest way: let an AI agent do it

If you use an AI coding agent (Claude Code, Codex, Cursor, Copilot agent mode, etc.), open this repo folder in it and paste:

```
Read AGENTS.md in this folder and follow it to check whether my PC is affected by the MSI Center "GET_ALL fail" bug and, if it is, apply the fix. Ask me before every step that changes my system.
```

[AGENTS.md](AGENTS.md) walks the agent through everything safely:
- check the log;
- verify the module hash and refuse unsupported versions;
- install the .NET SDK if needed;
- explain what will change and ask before doing it;
- run the installer;
- verify the result.

## Download

**Code → Download ZIP** on this page and extract it anywhere. Or use `git clone https://github.com/lostintired/msi-psu-getall-fix`.

## Requirements

- Windows 10/11 and MSI Center with the Power Supply Unit component, module version **1.0.0.38**. Other versions are refused and nothing is changed.
- [.NET 10 SDK](https://dotnet.microsoft.com/download), used to build the patcher.
- Administrator rights.

## Install

Run in an **administrator** PowerShell, from the repo folder:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

The script:
1. checks that the module is the original 1.0.0.38 (SHA-256 `F7833895…0274BB`);
2. copies it to `C:\Program Files\MsiPsuGetAllFix\` as a backup;
3. builds the patcher, patches the copy, and checks the result (SHA-256 `6535FEB9…5D2B46`; the patch is deterministic);
4. swaps the module in and restarts `MSI_Center_Service`. MSI Center reloads all its components, which takes a few seconds;
5. registers the scheduled task **"MSI PSU GET_ALL fix guard"**. It runs at logon and daily:
   - if an MSI Center update restored the original 1.0.0.38, it patches again;
   - if a *different* version appears, it changes nothing and shows a notification. MSI may have fixed the bug, or the patcher needs updating.

Use `-NoGuard` to skip the task, or `-MsiCenterDir "D:\...\MSI Center"` if MSI Center is not in the default location.

Check afterwards: run `scripts\check-log.ps1` after a few minutes. No new lines should appear after the install time.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\MsiPsuGetAllFix\uninstall.ps1"
```

This restores the original module, restarts the service, and removes the task and the install folder.

## Caveats

- MSI's Authenticode signature on the patched DLL is no longer valid. MSI Center doesn't check it (it loads components with `Assembly.LoadFile`), but an antivirus might complain.
- Only module 1.0.0.38 is supported. A future MSI update may fix the bug or change the code. In both cases the guard leaves the new module alone.
- Tested on one system: MEG Ai1300P (USB `VID_0DB0&PID_56D4`), MSI Center 2.0.74.0, SDK 3.2026.0911.01. The same code path serves two more PSU models (product IDs 59209 and 51691). Reports from other models are welcome.
- Use at your own risk. This is not affiliated with MSI. The bug has been reported to MSI support.

## License

MIT for the code in this repo. MSI Center and its components belong to MSI.
