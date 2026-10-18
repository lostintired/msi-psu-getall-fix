// Fixes the false "Read data of PSU GET_ALL fail" errors of MSI Center's Power Supply Unit
// component (API_Power Supply Unit.dll 1.0.0.38).
// cPSU.Get rejects every reply whose buffer[3] == 0xFE. For GET_ALL (0xE0) buffer[3] is the low byte
// of the +12V reading in PMBus LINEAR11 format (0xD2FE = 11.969 V), so valid replies are thrown away.
// The patch skips the 0xFE check for command 0xE0; all other commands behave as before.
// The target assembly is read as data (dnlib); it is never loaded or executed.
// Usage: patcher <original.dll> <output.dll> <expected SHA-256 of the original>
using System.Security.Cryptography;
using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Writer;

if (args.Length != 3) { Console.Error.WriteLine("usage: patcher <in.dll> <out.dll> <sha256>"); return 2; }
var (input, output, expected) = (args[0], args[1], args[2]);

var hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(input)));
if (!hash.Equals(expected, StringComparison.OrdinalIgnoreCase)) { Console.Error.WriteLine($"SHA-256 mismatch: {hash}"); return 3; }

var module = ModuleDefMD.Load(input);
var type = module.Find("API_PSUMonitor.cPSU", false) ?? throw new Exception("cPSU not found");
var method = type.Methods.SingleOrDefault(m => m.Name == "Get") ?? throw new Exception("cPSU.Get not found");
var body = method.Body;
body.SimplifyMacros(method.Parameters);
body.SimplifyBranches();
var il = body.Instructions;

// The check: ldarg.2 ldind.ref ldc.i4.3 ldelem.u1 ldc.i4 254 bne.un <ok>
var hits = new List<int>();
for (int i = 0; i + 5 < il.Count; i++)
{
    if (il[i].OpCode == OpCodes.Ldarg && il[i].Operand is Parameter p && p.MethodSigIndex == 2
        && il[i + 1].OpCode == OpCodes.Ldind_Ref
        && il[i + 2].OpCode == OpCodes.Ldc_I4 && (int)il[i + 2].Operand == 3
        && il[i + 3].OpCode == OpCodes.Ldelem_U1
        && il[i + 4].OpCode == OpCodes.Ldc_I4 && (int)il[i + 4].Operand == 254
        && il[i + 5].OpCode == OpCodes.Bne_Un)
        hits.Add(i);
}
if (hits.Count != 1)
{
    Console.Error.WriteLine($"pattern matches: {hits.Count}, expected 1");
    foreach (var h in hits) for (int k = h; k <= h + 5; k++) Console.Error.WriteLine($"  [{h}] {il[k]}");
    return 4;
}

int at = hits[0];
var checkStart = il[at];
var accepted = (Instruction)il[at + 5].Operand;
var cmdArg = method.Parameters.Single(p => p.MethodSigIndex == 1);
var skip = new[]
{
    OpCodes.Ldarg.ToInstruction(cmdArg),
    OpCodes.Ldc_I4.ToInstruction(0xE0),
    OpCodes.Beq.ToInstruction(accepted),
};
// Branches to the start of the check must now land on the inserted code.
foreach (var ins in il)
    if (ins.Operand == checkStart) ins.Operand = skip[0];
foreach (var eh in body.ExceptionHandlers)
{
    if (eh.TryStart == checkStart) eh.TryStart = skip[0];
    if (eh.HandlerStart == checkStart) eh.HandlerStart = skip[0];
    if (eh.TryEnd == checkStart) eh.TryEnd = skip[0];
    if (eh.HandlerEnd == checkStart) eh.HandlerEnd = skip[0];
}
for (int k = 0; k < skip.Length; k++) il.Insert(at + k, skip[k]);
body.OptimizeBranches();
body.OptimizeMacros();

var opts = new ModuleWriterOptions(module);
opts.MetadataOptions.Flags |= MetadataFlags.PreserveAll;
module.Write(output, opts);
Console.WriteLine($"patched cPSU.Get at instruction {at}; out SHA-256 {Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(output)))}");
return 0;
