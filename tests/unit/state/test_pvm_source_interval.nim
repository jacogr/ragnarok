# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine folded source spans and paid suffixes keep interval structure separate from header authority.

import std/[assertions, syncio]
import ../../../src/pvm/[program, machine, step]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/internal/handler_stream

proc owner(parts: openArray[seq[byte]]): Program =
  ## Literal opcode boundaries describe small real programs without exposing captured frame collections.
  var code: seq[byte] = @[]
  var starts: seq[int] = @[]
  for part in parts:
    starts.add(code.len)
    for octet in part: code.add(octet)
  assert code.len < 128, "literal source framing bound"
  var raw = @[0'u8, 0, byte(code.len)]
  for octet in code: raw.add(octet)
  var bitmap = newSeq[byte]((code.len+7) div 8)
  for start in starts: bitmap[start div 8] = bitmap[start div 8] or (1'u8 shl (start mod 8))
  for octet in bitmap: raw.add(octet)
  let decoded = decodeProgram(raw, CodeAddress(0), ProgramByteLimit(256), JumpCountLimit(0))
  assert decoded.error == ProgramError.None, "literal source admission"
  decoded.value

proc noops(span: int): Program =
  ## Every source fact except the final trap is a genuine folded one-byte noop.
  var parts: seq[seq[byte]] = @[]
  for ordinal in 0..<span-1: parts.add(@[2'u8])
  parts.add(@[0'u8])
  owner(parts)

proc initial(pc: uint64 = 0, paid: bool = false): MachineInfo =
  ## All calls start from copied CPU values, with no memory or host capability to borrow.
  MachineInfo(pc: CodeAddress(pc), gas: MachineGas(100000),
    registers: default(RegisterFile), blockCharged: paid)

const Sentinel = [11'u64, 22'u64, 33'u64, 44'u64, 55'u64]

for span in [64, 65, 66]:
  # The complete header is genuinely emitted even when a one-attempt stop lands inside folded noops.
  var frame = newFlatFrame(newFlatPlan(noops(span), GasCycleLimit(10000)), [], initial())
  runFlat(frame, 1)
  assert frame.reason == StepError.StepLimitExceeded and uint64(frame.info.pc) == 1,
    "literal folded-noop stop"
  let before = frame.info
  let remaining = frame.remaining
  let nodes = flatNodes(frame)
  for cap in [64'u32, 65'u32]:
    # Caller caps remain distinct: 65 source facts do not acquire ARM's 64-fact authority.
    var fields = Sentinel
    let accepted = flatSourceIntervalProof(frame, 0, cap, fields)
    assert accepted == (span <= int(cap)), "distinct source-span caps"
    if accepted:
      assert fields[1] == 0 and fields[2] == uint64(span-1) and fields[3] == uint64(span),
        "literal complete folded source span"
      when defined(pvmX86Jit):
        assert flatX86CompleteTargetWitness(frame, uint32(fields[0])), "genuine complete target"
    else:
      assert fields == Sentinel, "failed interval leaves copied output untouched"
  var missing = Sentinel
  assert not flatSourceIntervalProof(frame, high(uint32), 65, missing) and missing == Sentinel,
    "missing captured PC refusal"
  assert not flatSourceIntervalProof(frame, 0, 0, missing) and missing == Sentinel,
    "zero caller cap refusal"
  assert frame.info == before and frame.remaining == remaining and flatNodes(frame) == nodes,
    "proof query does not execute or resolve source"

block paidInterior:
  # Cached paid reentry uses its existing body; a fresh paid entry must first capture a suffix header.
  let plan = newFlatPlan(noops(8), GasCycleLimit(10000))
  var frame = newFlatFrame(plan, [], initial())
  runFlat(frame, 1)
  var fields = Sentinel
  assert not flatSourceIntervalProof(frame, 1, 65, fields) and fields == Sentinel,
    "folded interior coordinate is not yet a captured complete entry"
  resetFlatFrame(frame, initial(1, true))
  let cachedNodes = flatNodes(frame)
  runFlat(frame, 1)
  assert uint64(frame.info.pc) == 2 and flatNodes(frame) == cachedNodes,
    "literal cached paid noop without suffix emission"
  assert not flatSourceIntervalProof(frame, 1, 65, fields) and fields == Sentinel,
    "paid cached interior retains its original body coordinate"
  var fresh = newFlatFrame(plan, [], initial(1, true))
  runFlat(fresh, 1)
  let before = fresh.info
  let nodes = flatNodes(fresh)
  assert flatSourceIntervalProof(fresh, 1, 65, fields), "genuinely captured fresh paid suffix interval"
  assert fields[1] == 1 and fields[2] == 7 and fields[3] == 7, "literal paid suffix coordinates"
  when defined(pvmX86Jit):
    assert not flatX86CompleteTargetWitness(fresh, uint32(fields[0])),
      "structural suffix has no original-priced-header authority"
  assert fresh.info == before and flatNodes(fresh) == nodes, "suffix proof is read only"

block interiorNoops:
  # Both leading/interior folding and three real emitted operations preserve five source attempts.
  let program = owner([@[2'u8], @[51'u8, 2, 5], @[2'u8], @[149'u8, 0x22, 1], @[0'u8]])
  var frame = newFlatFrame(newFlatPlan(program, GasCycleLimit(10000)), [], initial())
  runFlat(frame, 5)
  assert frame.reason == StepError.None and frame.exit == StepExit.Panic and frame.remaining == 0,
    "literal five-attempt folded block"
  var wanted = default(RegisterFile)
  wanted[2] = RegisterValue(6)
  assert frame.info.registers == wanted, "literal scalar effects across folded noops"
  var fields = Sentinel
  assert flatSourceIntervalProof(frame, 0, 64, fields) and fields[1] == 0 and
    fields[2] == 4 and fields[3] == 5, "source span retains both folded noops"
  when defined(pvmX86Jit):
    assert flatX86CompleteTargetWitness(frame, uint32(fields[0])), "complete nonnoop site proof"

echo "PVM source interval passed"
