# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full-container boundary, immutable ownership and bounded standalone CLI witnesses.
import std/[assertions, syncio, strutils, tempfiles, paths, files]
import ../../../src/pvm/[artifact, program, machine, step, gas]
import ../../../src/codec/natural
import ../../../src/app/[options, pvm_command, cli_help]

proc natural(bytes: var seq[byte], value: uint64) =
  ## Construct fixture lengths using the independently maintained canonical prefix codec.
  let encoded = encode(JamNatural(value))
  for i in 0..<encoded.len:
    bytes.add(encoded.bytes[i]) # Copy only the encoded extent, never its unused tail.

proc section(bytes: var seq[byte], id: byte, contents: seq[byte]) =
  ## Keep framing separate from semantic payload mutations in the witnesses below.
  bytes.add(id)
  natural(bytes, uint64(contents.len))
  for octet in contents:
    bytes.add(octet) # No fixture aliases the caller's mutable payload.

proc seal(bytes: var seq[byte]) =
  ## Patch the documented complete-container LE64 length after a controlled fixture mutation.
  for i in 0..<8:
    bytes[5+i] = byte((uint64(bytes.len) shr (i*8)) and 255)

proc fixture(code: seq[byte] = @[0'u8, 0, 2, 50, 0, 1], entry = 0'u8,
    version = 3'u8, malformedImports = false, overflowMemory = false): seq[byte] =
  ## A real host-free dynamic halt has RO/RW data, one import, an export and optional metadata.
  result = @[byte('P'), byte('V'), byte('M'), 0, version, 0, 0, 0, 0, 0, 0, 0, 0]
  var config: seq[byte] = @[]
  natural(config, if overflowMemory: uint64(high(uint32)) else: 3'u64)
  natural(config, 3)
  natural(config, 4096)
  section(result, 1, config)
  section(result, 2, @[7'u8, 8, 9])
  section(result, 3, @[10'u8, 11, 12])
  section(result, 4, @[1'u8, (if malformedImports: 2'u8 else: 0'u8), 0, 0, 0, byte('h')])
  section(result, 5, @[1'u8, entry, 4, byte('m'), byte('a'), byte('i'), byte('n')])
  section(result, 6, code)
  section(result, 200, @[99'u8])
  result.add(0)
  seal(result)

proc refused(bytes: seq[byte], reason: ArtifactError) =
  ## Failures expose only their reason, never a partial memory/program or a fabricated entry.
  assert decodeArtifact(bytes).error == reason

let raw = fixture()
let loaded = decodeArtifact(raw)
assert loaded.error == ArtifactError.None
let owned = loaded.value
assert owned.valid and owned.entry("main").error == ArtifactError.None
assert uint64(owned.entry("main").value) == 0
assert owned.entry("missing").error == ArtifactError.MissingExport
assert default(Artifact).entry("main").error == ArtifactError.Uninitialized
let absentResult = default(ArtifactResult[Artifact])
assert absentResult.error == ArtifactError.Uninitialized
let memory = memoryOf(owned)
assert uint64(load(memory, MemoryAddress(65536), AccessWidth(1)).value) == 7
assert uint64(load(memory, MemoryAddress(196608), AccessWidth(1)).value) == 10
assert load(memory, MemoryAddress(131072), AccessWidth(1)).error == MachineError.Fault
assert store(memory, MemoryAddress(65536), AccessWidth(1), RegisterValue(1)).error ==
    MachineError.Fault
let initial = initialMachine(owned, "main", MachineGas(100))
assert initial.error == ArtifactError.None
let info = machineInfo(initial.value).value
assert uint64(info.registers[0]) == 0xffff0000'u64
assert uint64(info.registers[1]) == 0xfffe0000'u64
let execution = execute(initial.value, ExecutionStepLimit(10), GasCycleLimit(100),
    PvmBackend.Interpreted)
assert execution.error == StepError.None and execution.value.exit == StepExit.Halt
var changed = raw
changed[0] = 0
assert owned.entry("main").error == ArtifactError.None
var symbols = importSymbols(owned)
symbols[0] = "changed"
assert importSymbols(owned) == @["h"]
for length in 0..<raw.len:
  # Every proper prefix is invalid both with the original length and after an attacker reseals it.
  var truncated = raw[0..<length]
  assert decodeArtifact(truncated).error != ArtifactError.None
  if length >= 13:
    seal(truncated)
    assert decodeArtifact(truncated).error != ArtifactError.None
refused(fixture(version = 0), ArtifactError.UnsupportedVersion)
refused(fixture(version = 2), ArtifactError.UnsupportedVersion)
refused(fixture(entry = 1), ArtifactError.InvalidProgram)
refused(fixture(malformedImports = true), ArtifactError.InvalidFormat)
refused(fixture(overflowMemory = true), ArtifactError.InvalidMemory)
refused(fixture(code = @[0'u8]), ArtifactError.InvalidProgram)
var trailing = raw
trailing.add(0)
seal(trailing)
refused(trailing, ArtifactError.InvalidFormat)
var duplicate = raw[0..<raw.len-1]
section(duplicate, 2, @[])
duplicate.add(0)
seal(duplicate)
refused(duplicate, ArtifactError.InvalidFormat)
var noncanonical = raw[0..<13]
noncanonical.add(1)
noncanonical.add(128)
noncanonical.add(0)
noncanonical.add(0)
seal(noncanonical)
refused(noncanonical, ArtifactError.InvalidFormat)
var limits = defaultArtifactLimits()
limits.bytes = uint64(raw.len-1)
assert decodeArtifact(raw, limits).error == ArtifactError.LimitExceeded
limits = defaultArtifactLimits()
limits.pages = 2
assert decodeArtifact(raw, limits).error == ArtifactError.LimitExceeded
limits = defaultArtifactLimits()
limits.symbols = 0
assert decodeArtifact(raw, limits).error == ArtifactError.LimitExceeded
limits = defaultArtifactLimits()
limits.codeBytes = 1
assert decodeArtifact(raw, limits).error == ArtifactError.LimitExceeded

assert "--pvm-code FILE" in commandHelp()
assert "--pvm-code" notin commandHelp("server")
var parsed = default(Options)
var diagnostic = ""
assert parseOptions(@["--pvm-code", "hello.polkavm", "--pvm-backend", "interpreted"], parsed, diagnostic)
assert parsed.pvmCodePath == "hello.polkavm" and parsed.pvmEntry == "main"
assert parsed.pvmGas == 10000000 and parsed.pvmSteps == 10000000
assert parseOptions(@["--pvm-backend=jit", "--pvm-code=hello.polkavm", "--pvm-entry=run",
    "--pvm-gas=7", "--pvm-steps=9"], parsed, diagnostic)
assert parsed.pvmEntry == "run" and parsed.pvmGas == 7 and parsed.pvmSteps == 9
for rejected in [@["--pvm-entry", "main"], @["--pvm-code"],
    @["--pvm-code", "x", "--pvm-gas", "0"],
    @["--pvm-code", "x", "--pvm-steps", "1000000001"],
    @["--pvm-code", "x", "--pvm-gas", "18446744073709551616"],
    @["--pvm-code", "x", "--pvm-code", "y"],
    @["--pvm-code", "x", "--with-rpc"],
    @["--selftest", "--pvm-code", "x"]]:
  # A previous successful parse must not survive a later malformed or ignored configuration.
  assert not parseOptions(rejected, parsed, diagnostic)
  assert not parsed.valid and parsed.pvmCodePath.len == 0 and parsed.pvmGas == 0
assert parseOptions(@["--pvm-code", "/missing/pvm-artifact-test.polkavm"], parsed, diagnostic)
assert not runPvmCode(parsed, diagnostic) and "IoError" in diagnostic
try:
  # Filesystem failures terminate this witness rather than bypassing its assertions.
  let temporary = createTempFile("ragnarok-artifact-cli-", ".polkavm")
  close(temporary.cfile)
  let path = $temporary.path
  try:
    # Real bounded file IO and the command handler use the same production parser and interpreter owner.
    var contents = newString(raw.len)
    for i, octet in raw: contents[i] = char(octet)
    writeFile(path, contents)
    assert parseOptions(@["--pvm-code", path, "--pvm-backend", "interpreted"], parsed, diagnostic)
    assert runPvmCode(parsed, diagnostic), diagnostic
    assert "PVM_CODE_OK" in diagnostic and "actual=interpreted" in diagnostic
    assert loadArtifact(path).error == ArtifactError.None
    assert parseOptions(@["--pvm-code", path, "--pvm-entry", "missing"], parsed, diagnostic)
    assert not runPvmCode(parsed, diagnostic) and "MissingExport" in diagnostic
    let host = fixture(code = @[0'u8, 0, 2, 10, 0, 1])
    contents = newString(host.len)
    for i, octet in host: contents[i] = char(octet)
    writeFile(path, contents)
    assert parseOptions(@["--pvm-code", path, "--pvm-backend", "interpreted"], parsed, diagnostic)
    assert not runPvmCode(parsed, diagnostic) and "unbound-host=0" in diagnostic
    let loop = fixture(code = @[0'u8, 0, 2, 40, 0, 1])
    contents = newString(loop.len)
    for i, octet in loop: contents[i] = char(octet)
    writeFile(path, contents)
    assert parseOptions(@["--pvm-code", path, "--pvm-backend", "interpreted", "--pvm-steps", "1"],
        parsed, diagnostic)
    assert not runPvmCode(parsed, diagnostic) and "StepLimitExceeded" in diagnostic
    let panic = fixture(code = @[0'u8, 0, 1, 0, 1])
    contents = newString(panic.len)
    for i, octet in panic: contents[i] = char(octet)
    writeFile(path, contents)
    assert parseOptions(@["--pvm-code", path, "--pvm-backend", "interpreted"], parsed, diagnostic)
    assert not runPvmCode(parsed, diagnostic) and "Panic" in diagnostic
  finally:
    removeFile(temporary.path) # The fixture never persists outside this test's explicit lifetime.
except:
  assert false, "artifact fixture filesystem operation failed"
stdout.writeLine("pvm artifact tests passed")
