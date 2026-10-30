# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Source-preparation interface refusal leaves ordinary plan and stream ownership unchanged.
import std/[assertions, syncio]
import ../../../src/pvm/[program, machine]
import ../../../src/pvm/gas/gas
import ../../../src/pvm/step
import ../../../src/pvm/internal/handler_stream

type PreviousFlatError {.pure.} = enum
  ## The previous ordinal range is a representation-size control, not a second error API.
  Uninitialized, None, InvalidPolicy, InvalidProgram, CodeLimitExceeded, FactLimitExceeded,
    JumpLimitExceeded, PageLimitExceeded, StreamLimitExceeded, PreparationLimitExceeded,
      InvalidMemory

block errorRepresentation:
  # Appending source-facility reasons must not enlarge an existing frame/result discriminator.
  assert sizeof(FlatError) == sizeof(PreviousFlatError)
  assert ord(FlatError.Uninitialized) == 0 and ord(FlatError.None) == 1
  assert ord(FlatError.InvalidPolicy) == 2 and ord(FlatError.InvalidProgram) == 3
  assert ord(FlatError.CodeLimitExceeded) == 4 and ord(FlatError.FactLimitExceeded) == 5
  assert ord(FlatError.JumpLimitExceeded) == 6 and ord(FlatError.PageLimitExceeded) == 7
  assert ord(FlatError.StreamLimitExceeded) == 8 and ord(FlatError.PreparationLimitExceeded) == 9
  assert ord(FlatError.InvalidMemory) == 10 and ord(FlatError.NativeNotBuilt) == 11
  assert ord(FlatError.NativePlatformUnsupported) == 12
  assert ord(FlatError.NativeStorageUnavailable) == 13

proc unsealed(stream: FlatStream) =
  ## A copied observation cannot mutate or turn an ordinary stream into a prepared capability.
  let facts = streamSealedInfo(stream)
  assert not facts.sealed
  assert facts.candidates == 0 and facts.nativeEntries == 0
  assert facts.checkedEntries == 0 and facts.capacityDeferred == 0
  when defined(pvmSourceSealingReceipt):
    assert facts.compilationPasses == 0
  var changed = facts
  changed.sealed = true
  changed.candidates = 1
  assert not streamSealedInfo(stream).sealed
  assert streamSealedInfo(stream).candidates == 0

# One genuine halt program gives both native-enabled and forced-interpreted plans identical source.
let decoded = decodeProgram(@[0'u8, 0, 2, 50, 0, 1], CodeAddress(0), ProgramByteLimit(64),
  JumpCountLimit(0))
assert decoded.error == ProgramError.None
let cycles = GasCycleLimit(1000)
let empty = default(FlatResult[FlatStream])
assert empty.error == FlatError.Uninitialized

for allowNative in [false, true]:
  # This facility's absence does not change the ordinary JIT build or interpretation policy.
  var admitted = prepareFlatPlan(decoded.value, cycles, defaultFlatLimits(), allowNative)
  assert admitted.error == FlatError.None
  let plan = takeValue(admitted)
  let facts = planFacts(plan)
  let refused = prepareFlatStream(plan)
  assert refused.error == FlatError.NativeNotBuilt
  assert planFacts(plan) == facts
  assert prepareFlatStream(plan).error == FlatError.NativeNotBuilt
  var registers = default(RegisterFile)
  registers[0] = RegisterValue(0xffff0000'u64)
  var frame = newFlatFrame(plan, [], MachineInfo(gas: MachineGas(100), registers: registers))
  runFlat(frame, 1)
  assert frame.reason == StepError.None and frame.exit == StepExit.Halt
  var stream = takeFlatStream(frame)
  unsealed(stream)
  restoreFlatStream(frame, stream)
  assert preparationError(frame) == FlatError.None

var initial = default(FlatStream)
unsealed(initial)
assert streamNodes(initial) == 0 and streamPreparation(initial) == 0
echo "PASS source preparation API / explicit unavailable / copied unsealed facts / ordinary compatibility"
