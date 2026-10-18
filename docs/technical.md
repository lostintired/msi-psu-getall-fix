# Technical details

## Polling chain

`MSI_Center_Service` (MSI_Central_Service.exe, LocalSystem) → `MSI.CentralServer.exe` → plugin `Power Supply Unit\API_Power Supply Unit.dll` (.NET, loaded with `Assembly.LoadFile`, no strong name) → `MsiHid.dll` (native HID wrapper, 100 ms overlapped waits) → USB HID, interrupt OUT 0x01 / IN 0x81, 64-byte reports.

`C_PSU._timerMonitor_Tick` runs every 1000 ms. For PIDs 59209, 22228 (0x56D4, MEG Ai1300P) and 51691 it calls GET_ALL up to 6 times in a row, with no delay, until one reply is accepted. After 6 rejections it logs `Read data of PSU GET_ALL fail... (n)`. Here `n` is the `countMoinitorFail` field. It grows on every failed attempt and resets when non-zero data is accepted, which is why `(12)` and `(18)` also appear.

## The reply

Request: `51 E0 00 …`. Reply: `51 E0` followed by little-endian 16-bit PMBus LINEAR11 words. A real reply:

```
51 e0 | fe d2 | 00 f0 | fe d2 | 17 f0 | fe d2 | 01 f0 | fe d2 | 10 f0 | fe d2 | 09 f0 | fe d2 | 26 f0 | 81 ca | 46 e0 | ab c9 | …
```

| bytes | LINEAR11 | meaning (matches the MSI Center UI) |
|---|---|---|
| `fe d2` / `fd d2` / `ff d2` | 11.969 / 11.953 / 11.984 | +12V, V |
| `00 f0`, `12 f0`, `10 f0`, `09 f0` | 0 / 4.5 / 4.0 / 2.25 | 12V rail currents, A |
| `81 ca` | 5.008 | +5V, V |
| `ab c9` | 3.336 | +3.3V, V |

LINEAR11: the high 5 bits are a signed exponent, the low 11 bits a signed mantissa. `0xD2FE`: exponent `0b11010` = −6, mantissa `0x2FE` = 766, so 766 / 64 = 11.969.

## The bug

`API_PSUMonitor.cPSU.Get(cmd, ref byte[] buffer, …)` validates the reply header. Then, for every command, it does:

```csharp
if (buffer[3] == 0xFE) return false;   // IL: ldarg.2 ldind.ref ldc.i4.3 ldelem.u1 ldc.i4 254 bne.un
```

For GET_ALL, `buffer[3]` is the low byte of the +12V word. Whenever +12V reads 11.969 V, all 6 attempts are rejected and the error is logged. Neighbouring readings (`0xFD`, `0xFF`, `0xFB`, …) pass.

## Evidence (USBPcap captures, 10 minutes each)

| | original | v1: 5 ms pause between retries | v2: this patch |
|---|---|---|---|
| `GET_ALL fail` in log | 36 | 49 | 0 |
| failures matching a burst of 6 `fe d2` replies | 36 / 36 | 49 / 49 | — |
| reply latency | ~2 ms | ~2 ms | ~2 ms |

- USB is healthy: every transfer succeeds and replies arrive within ~2 ms, far from the 100 ms timeout. No overlapping requests were seen, so there is no second reader interfering.
- The first guess was that `0xFE` meant "busy, not ready", so v1 added a pause between retries. It made no difference: the "busy" runs lasted ~78 ms because the voltage simply stayed at 11.969 V. That led to decoding the reply.

## The patch

Before the check, insert:

```
ldarg   cmd
ldc.i4  0xE0
beq     <accepted>
```

The patcher (dnlib) requires exactly one match of the check pattern in `cPSU.Get`. It retargets branches and exception-handler bounds that pointed at the old check start, and writes the module with `MetadataFlags.PreserveAll`. An IL diff shows that only `cPSU.Get` changes.

| file | SHA-256 |
|---|---|
| original 1.0.0.38 | `F7833895191630412D25A9C3773284F6303AEDA8E7256689526EC4A91B0274BB` |
| patched | `6535FEB9E45D195A2B5243680EB369F5408349DD4CEDA9D1A1BF6A77155D2B46` |

## Updates

MSI Center updates components with a silent SDK installer (`MSI Center SDK.exe /verysilent`), which overwrites the module. The guard task re-applies the patch only if the exact original 1.0.0.38 comes back. A newer version is left alone and you get a notification.

## Open questions

- Replies to commands `0x42` (`0x01`) and `0xE1` (`0x00`). They are unrelated to the errors.
- When the module logs `Read 0 value`. It was not seen during testing.
