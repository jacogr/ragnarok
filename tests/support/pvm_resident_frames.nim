# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Populate actual Frame/result/scratch owners for ordinary borrowed-assignment rejection checks.
import std/[assertions, syncio]
import ../../src/pvm/[program, machine]
import ../../src/pvm/gas/gas
import ../../src/pvm/internal/handler_stream

proc populatedFrameResult*(): FlatResult[FlatFrame] =
  ## A genuine admitted source constructs the actual exclusive frame success payload.
  let decoded = decodeProgram(@[0'u8, 0, 1, 0, 1], CodeAddress(0), ProgramByteLimit(5),
      JumpCountLimit(0))
  assert decoded.error == ProgramError.None
  let owner = decoded.value
  var admitted = prepareFlatPlan(owner, GasCycleLimit(10000), defaultFlatLimits(), false)
  assert admitted.error == FlatError.None
  let plan = handler_stream.takeValue(admitted)
  let regions = [InitializationRegion(first: PageIndex(32), past: PageIndex(288),
    access: PageAccess.ReadWrite, source: InitializationSource.First, offset: 0, length: 0)]
  let memory = captureInitializationMemory(regions, [], [], PageLimit(256)).value
  result = prepareFlatMemoryFrame(plan, memory, MachineInfo(gas: MachineGas(10000)))
  assert result.error == FlatError.None

proc populatedFrame*(): FlatFrame =
  ## Transfer the populated frame result once; no bare resource pointer is fabricated.
  var created = populatedFrameResult()
  handler_stream.takeValue(created)

proc populatedScratch*(): FlatMemoryScratch =
  ## The real ARC heap payload owns the complete resident lease and immutable baseline.
  var frame = populatedFrame()
  let scratch = takeFlatMemoryScratch(frame, 2097152'u64)
  if scratch != nil:
    # Only the actual retained owner can satisfy this populated nonnil fixture contract.
    assert flatMemoryScratchPayload(scratch) == 2097152'u64
    return scratch
  else:
    # Setup refusal must not become a fabricated payload or the intended ownership rejection.
    quit "resident scratch fixture initialization failed"
