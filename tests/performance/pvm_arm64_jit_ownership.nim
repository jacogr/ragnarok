# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Local lowering witness: exclusive frame/stream owners can move but cannot be duplicated for a later read.
import std/[assertions, syncio]
import ../../src/pvm/internal/handler_stream
import ../../src/pvm/program
import ../../src/pvm/gas/gas
import ../../src/pvm/machine

when defined(pvmArm64JitFrameOwner):
  proc consume(owner: sink FlatFrame): int =
    ## The consuming boundary forces genuine ownership lowering, rather than an optimized-away assignment.
    flatNodes(owner)
  let decoded = decodeProgram(@[0'u8, 0, 1, 0, 1], CodeAddress(0), ProgramByteLimit(64),
      JumpCountLimit(1))
  assert decoded.error == ProgramError.None
  var original = newFlatFrame(newFlatPlan(decoded.value, GasCycleLimit(100)), [],
    MachineInfo(pc: CodeAddress(0), gas: MachineGas(100), registers: default(RegisterFile)))
  when defined(pvmArm64JitMoveOwner):
    echo consume(move(original))
  else:
    echo consume(original)
  echo flatNodes(original)
else:
  proc consume(owner: sink FlatStream): uint64 =
    ## Stream code and fallback tables form one exclusive executable capability.
    streamNodes(owner)
  var original = default(FlatStream)
  when defined(pvmArm64JitMoveOwner):
    echo consume(move(original))
  else:
    echo consume(original)
  echo streamNodes(original)
