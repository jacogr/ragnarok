# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Isolated decoder/IR microbenchmark, using this checkout's public PVM APIs.
## Two arithmetic instructions only: no gas, memory, control flow or machine publication.

import std/[assertions, syncio, monotimes, envvars]
import ../../src/codec/natural
import ../../src/pvm/[program, machine, registers]

proc cpuNanoseconds(): int64 {.importc: "pvm_ir_cpu_nanoseconds", header: "cpu_clock.h".}
  ## OS process CPU clock excludes time descheduled by other work on this machine.

type
  Operation = object ## Compact scalar IR retains the guest PC for future exit mapping.
    pc: CodeAddress
    immediate: uint64
    destination, source: range[0..12]
    opcode: byte
  Fixture = object ## Validated owner and ordered guest PCs, shared by every engine.
    owner: Program
    pcs: seq[CodeAddress]
  Prepared = seq[ProgramResult[Instruction]] ## Full decoded results retain evaluator compatibility.

proc fixture(count: int): Fixture =
  ## Build actual JAM program framing; mixed immediate widths exercise the production decoder.
  assert count > 0 and count <= 256
  var code: seq[byte] = @[]
  var pcs: seq[CodeAddress] = @[]
  for i in 0..<count:
    # Variable byte lengths prevent every workload from having the same cache collision pattern.
    pcs.add(CodeAddress(code.len))
    code.add(if i mod 2 == 0: 149'u8 else: 133'u8)
    code.add(byte((i mod 8) + 16 * ((i + 7) mod 8)))
    let width = 1 + i mod 4
    for j in 0..<width:
      # Include negative immediates and full sign extension, rather than positive-only arithmetic.
      code.add(byte((i * 37 + j * 73 + 131) mod 256))
  code.add(0) # A final trap makes the supplied program valid; the timed harness excludes it.
  let length = encode(JamNatural(code.len))
  var wire: seq[byte] = @[0'u8, 0'u8]
  for i in 0..<length.len: wire.add(length.bytes[i])
  # Append individual bytes using the pinned sequence API.
  for value in code: wire.add(value)
  var mask = newSeq[byte]((code.len + 7) div 8)
  for pc in pcs:
    # Mark each opcode; immediate bytes remain unmarked regardless of their numeric contents.
    let at = int(uint64(pc))
    mask[at div 8] = mask[at div 8] or byte(1 shl (at mod 8))
  let last = code.len - 1
  mask[last div 8] = mask[last div 8] or byte(1 shl (last mod 8))
  # The bitmap follows code bytes in canonical program framing.
  for value in mask: wire.add(value)
  let decoded = decodeJamProgram(wire, CodeAddress(0), ProgramByteLimit(4096), JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  result = Fixture(owner: decoded.value, pcs: pcs)

proc prepare(f: Fixture): Prepared =
  ## Decode all selected instructions once without changing the existing register evaluator.
  result = @[]
  for pc in f.pcs:
    let item = instruction(f.owner, pc)
    assert item.error == ProgramError.None
    result.add(item)

proc lower(f: Fixture): seq[Operation] =
  ## Lower directly from the validated program to compact scalar operations.
  result = @[]
  for pc in f.pcs:
    let decoded = instruction(f.owner, pc)
    assert decoded.error == ProgramError.None
    let item = decoded.value
    assert item.opcode == 149 or item.opcode == 133
    result.add(Operation(pc: pc, opcode: item.opcode, immediate: uint64(item.x),
      destination: int(byte(item.a)), source: int(byte(item.b))))

proc initial(seed: uint64): RegisterFile =
  ## Seed all thirteen registers, including values close to unsigned overflow.
  result = default(RegisterFile)
  for i in 0..<13: result[i] = RegisterValue(seed xor (uint64(i) * 0x123456789abcdef'u64))

proc apply(decoded: ProgramResult[Instruction], cpu: var RegisterFile) {.inline.} =
  ## Every non-IR variant calls exactly the same production register evaluator.
  let evaluated = evaluateRegisters(decoded, cpu)
  assert evaluated.error == RegisterError.None
  cpu = evaluated.value

proc runDecode(f: Fixture, rounds: int, cpu: var RegisterFile) {.noinline.} =
  ## Baseline: repeat the public production decoder on every attempted arithmetic operation.
  for repeat in 0..<rounds:
    for pc in f.pcs: apply(instruction(f.owner, pc), cpu)

proc runCache(f: Fixture, rounds: int, cpu: var RegisterFile) {.noinline.} =
  ## Match the production memo's 16 direct-mapped full-PC-tagged slots and invocation lifetime.
  var entries = default(array[16, ProgramResult[Instruction]])
  var valid = default(array[16, bool])
  for repeat in 0..<rounds:
    for pc in f.pcs:
      let slot = int(uint64(pc) mod 16)
      if not valid[slot] or uint64(entries[slot].value.address) != uint64(pc):
        # Successful immutable operands only; a different PC replaces the slot.
        entries[slot] = instruction(f.owner, pc)
        assert entries[slot].error == ProgramError.None
        valid[slot] = true
      apply(entries[slot], cpu)

proc runPrepared(items: Prepared, rounds: int, cpu: var RegisterFile) {.noinline.} =
  ## Isolate decoding reuse while retaining the full production evaluator and dispatch.
  for repeat in 0..<rounds:
    for item in items: apply(item, cpu)

proc runIr(items: seq[Operation], rounds: int, cpu: var RegisterFile) {.noinline.} =
  ## Interpret the two lowered operations with checked array accesses and unsigned wrapping.
  for repeat in 0..<rounds:
    for item in items:
      let source = uint64(cpu[item.source])
      case item.opcode
      of 149: cpu[item.destination] = RegisterValue(source + item.immediate)
      of 133: cpu[item.destination] = RegisterValue(source xor item.immediate)
      else: assert false # Preparation must never admit another operation.

proc oracle(count, rounds: int, seed: uint64): RegisterFile =
  ## Independent scalar expectation derives operands from fixture construction, not decoding/IR.
  result = initial(seed)
  for repeat in 0..<rounds:
    for i in 0..<count:
      let width = 1 + i mod 4
      var immediate = 0'u64
      for j in 0..<width:
        immediate = immediate or (uint64((i * 37 + j * 73 + 131) mod 256) shl (8 * j))
      if ((i * 37 + (width - 1) * 73 + 131) mod 256) >= 128:
        # Extend the sign bit through the entire 64-bit register, including four-byte operands.
        immediate = immediate or (high(uint64) shl (8 * width))
      let source = uint64(result[(i + 7) mod 8])
      if i mod 2 == 0:
        result[i mod 8] = RegisterValue(source + immediate)
      else:
        result[i mod 8] = RegisterValue(source xor immediate)

proc same(a, b: RegisterFile) =
  ## Check the complete register file, including untouched registers, outside measured regions.
  for i in 0..<13: assert uint64(a[i]) == uint64(b[i])

proc execute(mode: int, f: Fixture, decoded: Prepared, ir: seq[Operation],
    rounds: int, cpu: var RegisterFile) =
  ## Select the engine once per timed region, outside the operation loop.
  case mode
  of 0: runDecode(f, rounds, cpu)
  of 1: runCache(f, rounds, cpu)
  of 2: runPrepared(decoded, rounds, cpu)
  of 3: runIr(ir, rounds, cpu)
  else: assert false

proc check() =
  ## Differential witnesses cover short/long sequences, zero work and unsigned wraparound.
  for count in [1, 2, 4, 32, 256]:
    let f = fixture(count)
    let decoded = prepare(f)
    let ir = lower(f)
    for seed in [0'u64, 1'u64, high(uint64)]:
      for rounds in [0, 1, 7, 113]:
        let expected = oracle(count, rounds, seed)
        for mode in 0..<4:
          var cpu = initial(seed)
          execute(mode, f, decoded, ir, rounds, cpu)
          same(cpu, expected)
  echo "CHECK,passed"

proc benchmark() =
  ## Rotate engine order, warm up three rounds, retain ten samples, validate every result.
  echo "LAYOUT,", sizeof(Instruction), ",", sizeof(ProgramResult[Instruction]), ",", sizeof(Operation)
  for count in [4, 32, 256]:
    let f = fixture(count)
    let decoded = prepare(f)
    let ir = lower(f)
    let rounds = 1048576 div count
    let expected = oracle(count, rounds, 12345)
    for sample in 0..<13:
      for order in 0..<4:
        let mode = (sample + order) mod 4
        var cpu = initial(12345)
        let start = getMonoTime().ticks
        let cpuStart = cpuNanoseconds()
        execute(mode, f, decoded, ir, rounds, cpu)
        let elapsed = getMonoTime().ticks - start
        let cpuElapsed = cpuNanoseconds() - cpuStart
        same(cpu, expected)
        if sample >= 3:
          echo "HOT,", count, ",", mode, ",", sample - 3, ",", elapsed, ",", rounds * count, ",", cpuElapsed
    let once = oracle(count, 1, 12345)
    for sample in 0..<13:
      for order in 0..<4:
        let mode = (sample + order) mod 4
        let start = getMonoTime().ticks
        let cpuStart = cpuNanoseconds()
        var checksum = 0'u64
        for trial in 0..<1000:
          # Cold regions include preparation/allocation and disposal, amortized over 1000 calls.
          var cpu = initial(12345)
          case mode
          of 0: runDecode(f, 1, cpu)
          of 1: runCache(f, 1, cpu)
          of 2:
            let items = prepare(f)
            runPrepared(items, 1, cpu)
          of 3:
            let items = lower(f)
            runIr(items, 1, cpu)
          else: assert false
          checksum = checksum xor (uint64(cpu[0]) + uint64(trial))
        let elapsed = getMonoTime().ticks - start
        let cpuElapsed = cpuNanoseconds() - cpuStart
        var expectedChecksum = 0'u64
        for trial in 0..<1000:
          expectedChecksum = expectedChecksum xor (uint64(once[0]) + uint64(trial))
        assert checksum == expectedChecksum
        if sample >= 3:
          echo "COLD,", count, ",", mode, ",", sample - 3, ",", elapsed, ",1000,", cpuElapsed
    for mode in 2..3:
      let start = getMonoTime().ticks
      let cpuStart = cpuNanoseconds()
      var lengths = 0
      for trial in 0..<1000:
        # Record preparation separately from warm execution, retaining actual allocations.
        if mode == 2:
          let items = prepare(f)
          lengths += items.len
        else:
          let items = lower(f)
          lengths += items.len
      let elapsed = getMonoTime().ticks - start
      let cpuElapsed = cpuNanoseconds() - cpuStart
      assert lengths == count * 1000
      echo "PREP,", count, ",", mode, ",0,", elapsed, ",1000,", cpuElapsed

if getEnv("PVM_IR_ASSERT_PROBE") == "1":
  # A negative control proves release assertions are active before accepting timing results.
  assert false, "pvm-ir assertion control"
check()
benchmark()
