# Instructions for AI coding agents

A user asked you to apply this fix on their Windows PC. Follow these steps in order and **ask the user before every step that changes the system** (marked ⚠).

1. Read `README.md` and `docs/technical.md`. Explain to the user in 2–3 sentences what the bug is and what the patch changes.
2. Check whether they are affected: run `powershell -ExecutionPolicy Bypass -File scripts\check-log.ps1` and show the result. If there are no `GET_ALL fail` lines, tell the user they don't need the fix, and stop.
3. Check the module: compute the SHA-256 of `C:\Program Files (x86)\MSI\MSI Center\Power Supply Unit\API_Power Supply Unit.dll` (or the user's MSI Center folder).
   - `F7833895191630412D25A9C3773284F6303AEDA8E7256689526EC4A91B0274BB` → supported original 1.0.0.38.
   - `6535FEB9E45D195A2B5243680EB369F5408349DD4CEDA9D1A1BF6A77155D2B46` → already patched.
   - Anything else → **stop**. This version is not supported. Do not try to adapt the patcher, and do not patch any other file.
4. Check for the .NET 10 SDK: `dotnet --list-sdks`. If it is missing, ⚠ ask the user, then install it with `winget install Microsoft.DotNet.SDK.10`.
5. ⚠ Tell the user what `scripts\install.ps1` will do, as listed in the README "Install" section. Mention that MSI Center restarts its components for a few seconds and that a scheduled task is added; offer `-NoGuard`. It must run in an **administrator** PowerShell. If your shell is not elevated, ask the user to run it themselves, or start it with `Start-Process powershell -Verb RunAs` so the user confirms the UAC prompt.
6. Verify: wait about 5 minutes and run `scripts\check-log.ps1` again. No new `GET_ALL fail` lines should appear after the install time. Also check that the log shows the component loaded: `Initialized ... 1 (OK)` in `MSI Center\Log\MSI Center\MSI Center_<date>.txt`.
7. Tell the user how to undo it: `C:\Program Files\MsiPsuGetAllFix\uninstall.ps1` as administrator.

Do not:
- download DLLs from anywhere or use a patched DLL from another source;
- edit other MSI Center files, services, the registry or Microsoft Store update settings;
- disable antivirus or SmartScreen;
- run load tests or extra tools that talk to the PSU over USB.
