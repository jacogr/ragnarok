# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared adopted GP #533/#538 grow_heap response for accumulation and refinement dispatch.
## Heap geometry comes from the caller's trusted initialization boundary; no context or publication effects.

import ./machine as pvm_machine
import ./step as pvm_step

type
  HeapHostError* {.pure.} = enum ## Local owner/capacity refusals remain distinct from protocol gas exhaustion.
    InvalidContext, LimitExceeded

proc growHeapResponse*(firstPage, pastPage: PageIndex, gas: MachineGas,
    registers: RegisterFile, memory: Memory): HostResult[HeapHostError] {.raises: [].} =
  ## Reuse the adopted no-growth price and zero-deficit OOG rule, with immutable atomic page growth.
  let counted = memory.writablePageCount(firstPage, pastPage)
  if counted.error != MachineError.None:
    return hostFailure(HeapHostError.InvalidContext) # No invalid memory owner supplies a synthetic endpoint.
  let first = uint64(uint32(firstPage))
  let past = uint64(uint32(pastPage))
  let count = uint64(uint32(counted.value))
  if first > past or count > past-first:
    return hostFailure(HeapHostError.InvalidContext) # Prove the endpoint addition before performing it.
  let current = first+count
  let requested = uint64(registers[7])
  var returned = current
  var cost = 275'u64
  if requested > current and requested <= past:
    # Both endpoints are <=2^20; the bounded difference times 121 plus 275 fits uint64.
    cost += (requested-current)*121
    returned = requested
  if uint64(gas) < cost:
    # #533 drains remaining credit and preserves registers/memory/context before row mutations; no signed debt.
    return hostSuccess[HeapHostError](HostResponse(action: HostAction.OutOfGas,
      gas: MachineGas(0), gasDeficit: GasDeficit(0), registers: registers, memory: memory))
  let grown = memory.withWritablePages(firstPage, PageIndex(uint32(returned)))
  case grown.error
  of MachineError.None:
    discard # Mapping preflight succeeded and all retained bytes/outside access remain immutable.
  of MachineError.LimitExceeded:
    return hostFailure(HeapHostError.LimitExceeded) # Local allocation capacity is distinct from protocol gas.
  else:
    return hostFailure(HeapHostError.InvalidContext) # No partial memory response escapes invariant failure.
  var response = HostResponse(action: HostAction.Continue,
    gas: MachineGas(uint64(gas)-cost), gasDeficit: GasDeficit(0),
    registers: registers, memory: grown.value)
  response.registers[7] = RegisterValue(returned)
  hostSuccess[HeapHostError](response)
