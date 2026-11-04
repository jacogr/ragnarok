# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Private literal scalar/branch residency, canonical bytes and actual six-register SysV controls.
import std/[assertions, envvars, syncio]
import ../../../src/codec/natural
import ../../../src/pvm/[program, machine, registers]
import ../../../src/pvm/internal/x86_jit

when not defined(pvmX86ResidentProof):
  assert false, "resident ISA controls require their explicit private define"

const
  Native = defined(linux) and defined(amd64) and not defined(pvmX86JitRefuse)
  Masks = [0'u32, 1, 0x3f, 0x1f80, 0x0aaa, 0x180f]
  Patterns = [0'u8, 17, 128, 255, 0x38, 0xc5]
  Seeds = [0'u64, 31, 64, 0x80000000'u64, 0x8000000000000000'u64, high(uint64)]

proc appendNatural(bytes: var seq[byte], value: uint64) =
  ## Only container framing uses the natural encoder; each original instruction is a literal byte row.
  let encoded = encode(JamNatural(value))
  for index in 0..<encoded.len: bytes.add(encoded.bytes[index])

proc literalOwner(opcode, pattern: byte): Program =
  ## A marked25-byte instruction plus panic supplies genuine saturated operand coordinates.
  var wire: seq[byte] = @[]
  appendNatural(wire, 0)
  wire.add(0)
  appendNatural(wire, 26)
  wire.add(opcode)
  for index in 0..<24: wire.add(pattern)
  wire.add(0)
  wire.add(1) # Original instruction starts at0.
  wire.add(0)
  wire.add(0)
  wire.add(2) # Panic starts at25; operands remain unmarked.
  let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(65536), JumpCountLimit(16))
  assert decoded.error == ProgramError.None
  decoded.value

proc initial(seed: uint64): RegisterFile =
  ## Distinct full-width sentinels expose stale resident reads and unwanted writes to all13 lanes.
  result = default(RegisterFile)
  for slot in 0..<13: result[slot] = RegisterValue(seed xor uint64(slot))

proc keepBytes(name: string, bytes: seq[byte]) =
  ## Optional cold byte exports compare the canonical wrapper against the frozen parent emitter.
  let directory = getEnv("RAGNAROK_PVM_RESIDENT_IMAGES")
  if directory.len == 0: return
  var data = newString(bytes.len)
  for index in 0..<bytes.len: data[index] = char(bytes[index])
  try:
    writeFile(directory & "/" & name & ".bin", data)
  except:
    quit 2

proc keepImage(name: string, body: X86Block) =
  ## Builder bytes and actual RX readback have separate artifact names.
  keepBytes(name, x86ResidentImageProof(body))

proc publish(jit: X86Jit, offset: var uint32, body: X86Block): uint32 =
  ## Raw backend controls count one literal operation; no Frame, plan, charge or source authority is invented.
  result = offset
  inc offset
  assert x86Entry(jit, result, 4096) == 0
  when Native:
    assert publishX86Entry(jit, result, result+1, 1, body, shortPrefix = true)

var jit = newX86Jit()
var next = 0'u32
var scalarCases = 0
var branchCases = 0
for numeric in 0..255:
  let opcode = byte(numeric)
  if not supportedX86Opcode(opcode): continue
  for pattern in Patterns:
    let source = literalOwner(opcode, pattern)
    let decoded = instruction(source, CodeAddress(0))
    assert decoded.error == ProgramError.None
    let slots = instructionRegisters(decoded)
    let value = uint64(decoded.value.x)
    var canonical = default(X86Block)
    emitX86Operation(canonical, opcode, slots, value)
    keepImage("scalar-" & $numeric & "-" & $pattern, canonical)
    let plain = publish(jit, next, canonical)
    for mask in Masks:
      # The same opcode switch selects canonical or resident reads/writes, never a second ALU implementation.
      let access = x86ResidentAccess(mask)
      var body = default(X86Block)
      beginX86Resident(body, access)
      emitX86ResidentOperation(body, access, opcode, slots, value)
      endX86Resident(body, access)
      let mapped = publish(jit, next, body)
      when Native:
        for seed in Seeds:
          var expected = initial(seed)
          let evaluated = evaluateRegisters(source, CodeAddress(0), expected)
          assert evaluated.error == RegisterError.None
          expected = evaluated.value
          var baseline = initial(seed)
          assert callX86Entry(jit, plain, baseline) == plain+1
          assert baseline == expected
          var actual = initial(seed)
          let receipt = callX86ResidentAbiProof(jit, mapped, actual)
          assert receipt shr 32 == 1 and actual == expected
          inc scalarCases

for numeric in 81..175:
  let opcode = byte(numeric)
  if opcode notin {81'u8..90, 170..175}: continue
  for pattern in Patterns:
    let source = literalOwner(opcode, pattern)
    let decoded = instruction(source, CodeAddress(0))
    assert decoded.error == ProgramError.None
    let slots = instructionRegisters(decoded)
    let value = uint64(decoded.value.x)
    var canonical = default(X86Block)
    emitX86Branch(canonical, opcode, slots, value, 123, 456)
    keepImage("branch-" & $numeric & "-" & $pattern, canonical)
    let plain = publish(jit, next, canonical)
    for mask in Masks:
      # RAX's selected scalar destination must survive every flush and restored callee-saved register.
      let access = x86ResidentAccess(mask)
      var body = default(X86Block)
      beginX86Resident(body, access)
      emitX86ResidentBranch(body, access, opcode, slots, value, 123, 456)
      endX86Resident(body, access)
      let mapped = publish(jit, next, body)
      when Native:
        for seed in Seeds:
          var baseline = initial(seed)
          let before = baseline
          let expected = callX86ResidentAbiProof(jit, plain, baseline)
          assert expected shr 32 == 1 and baseline == before
          var actual = before
          let receipt = callX86ResidentAbiProof(jit, mapped, actual)
          assert receipt == expected and actual == before
          inc branchCases

block everyHardwareDestination:
  # Fully aliased ADDs individually read/write RBX,RBP,R12,R13,R14,R15, not only their save slots.
  let access = x86ResidentAccess(0x3f)
  for lane in 0..<6:
    let source = literalOwner(149, byte(lane*17))
    let decoded = instruction(source, CodeAddress(0))
    assert decoded.error == ProgramError.None
    var body = default(X86Block)
    beginX86Resident(body, access)
    emitX86ResidentOperation(body, access, 149, instructionRegisters(decoded), 7)
    endX86Resident(body, access)
    let mapped = publish(jit, next, body)
    when Native:
      var actual = initial(0x8000000000000000'u64)
      var expected = actual
      expected[lane] = RegisterValue(uint64(expected[lane])+7)
      assert callX86ResidentAbiProof(jit, mapped, actual) shr 32 == 1
      assert actual == expected

block contextAndCurrentOperands:
  # Sequential mapped/unmapped writes then a mapped comparison expose current values, not entry snapshots.
  let access = x86ResidentAccess(0x1f80)
  let source = literalOwner(149, 0x88) # ADD64 R8,R8,+immediate.
  let decoded = instruction(source, CodeAddress(0))
  assert decoded.error == ProgramError.None
  let slots = instructionRegisters(decoded)
  var body = default(X86Block)
  beginX86Resident(body, access)
  emitX86ResidentContextProof(body)
  emitX86ResidentOperation(body, access, 149, slots, 1)
  emitX86ResidentOperation(body, access, 149, slots, 2)
  emitX86ResidentBranch(body, access, 81, slots, 103, 123, 456)
  endX86Resident(body, access)
  if getEnv("RAGNAROK_PVM_RESIDENT_BAD_ABI") == "1": clobberX86ResidentAbiProof(body)
  keepImage("resident-context", body)
  let mapped = publish(jit, next, body)
  when Native:
    var publishedBytes: seq[byte] = @[]
    var expectedBytes = x86ResidentImageProof(body)
    expectedBytes.add(0xc3) # Actual publisher appends the same final RET.
    assert copyX86ResidentImageProof(jit, mapped, uint32(expectedBytes.len), publishedBytes)
    assert publishedBytes == expectedBytes
    keepBytes("resident-context-rx", publishedBytes)
    var actual = initial(0)
    actual[8] = RegisterValue(100)
    var expected = actual
    expected[8] = RegisterValue(103)
    let receipt = callX86ResidentAbiProof(jit, mapped, actual, true)
    assert receipt == ((1'u64 shl 32) or 123'u64) and actual == expected
    assert getEnv("RAGNAROK_PVM_RESIDENT_BAD_ABI") != "1", "callee-clobber probe missed"

when Native:
  assert scalarCases == 11448 and branchCases == 3456
assert next < 4096
stdout.writeLine("X86_RESIDENT_ACCESS_OK")
