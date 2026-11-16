# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Assertion conveniences for valid test fixtures; production callers use checked admission and observation.

import std/assertions
import ../../src/pvm/[program, machine]
import ../../src/pvm/gas/gas
import ../../src/pvm/internal/handler_stream
import ../../src/pvm/internal/execution_types as oracle

proc newFlatPlan*(source: Program, cycles: GasCycleLimit): FlatPlan =
  ## A test fixture must satisfy ordinary default-policy admission before its owner is extracted.
  var prepared = prepareFlatPlan(source, cycles, defaultFlatLimits())
  assert prepared.error == FlatError.None
  takeValue(prepared)

proc newFlatFrame*(plan: FlatPlan, images: openArray[PageImage], info: MachineInfo): FlatFrame =
  ## Construct only an admitted test frame, preserving the runtime's explicit ownership transfer.
  var prepared = prepareFlatFrame(plan, images, info)
  assert prepared.error == FlatError.None
  takeValue(prepared)

proc flatMemorySnapshot*(frame: FlatFrame): Memory =
  ## Test snapshots must succeed through the same checked observation used by the public adapter.
  result = default(Memory)
  let observed = tryFlatMemorySnapshot(frame, result)
  assert observed == oracle.StepError.None

proc observeFlatHostMemory*(frame: var FlatFrame): Memory =
  ## Require a valid stopped host observation before inspecting its immutable memory owner.
  result = default(Memory)
  let observed = tryObserveFlatHostMemory(frame, result)
  assert observed == oracle.StepError.None

proc observeFlatHostScalars*(frame: var FlatFrame): MachineInfo =
  ## Require a real source-matched host stop before comparing scalar test expectations.
  result = default(MachineInfo)
  let observed = tryObserveFlatHostScalars(frame, result)
  assert observed == oracle.StepError.None

proc checkFlatSource*(frame: FlatFrame, expected: openArray[PageImage]) =
  ## A test assertion owns the independent baseline expectation; the runtime comparison itself never asserts.
  assert matchesFlatSource(frame, expected)

proc checkFlatReference*(frame: FlatFrame, expected: string, offset: int = 120) =
  ## Compare complete reference bytes outside performance clocks, retaining strict fixture failure.
  assert matchesFlatReference(frame, expected, offset)

proc replaceFlatMemory*(frame: var FlatFrame, images: openArray[PageImage], info: MachineInfo) =
  ## Test-only replacement requires success; runtime callers inspect the transactional refusal directly.
  let error = replaceFlatMemoryChecked(frame, images, info)
  assert error == FlatError.None
