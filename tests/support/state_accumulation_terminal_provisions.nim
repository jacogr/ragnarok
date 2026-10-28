# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual guest executions and explicit posterior maps for terminal-selected provision witnesses.
## Uses maintained public dispatch/assembly helpers; no forged contexts, outcomes or protocol verdicts.

import ../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../src/state/store as state_store
import ../../src/pvm/machine as pvm_machine
import ../../src/pvm/program as pvm_program
import ../../src/pvm/gas as pvm_gas
import ../../src/pvm/step as pvm_step
import ../../src/pvm/host_fetch as pvm_host_fetch
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/composite as codec_composite
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/state_trie as codec_state_trie
import ./pvm_accumulation_context
import ./pvm_accumulation_program
import ./pvm_accumulation_provision
import ./state_accumulation_provision_integration

type
  TerminalProvisionEnding* {.pure.} = enum ## Test-only terminal instructions drive genuine normalization paths.
    Halt,      ## Return normally with both regular provision contributions.
    Panic,     ## Trap after the second provide, selecting the earlier checkpoint.
    Fault,     ## Access unmapped memory after the second provide.
    OutOfGas,  ## Underfund a final host call after both provides.
    HashReturn ## Return 32 readable bytes while retaining the regular provision projection.

proc terminalPosteriorEntries*(): seq[StateEntry] =
  ## Requests and unrelated complete-map rows deliberately differ from invocation-owned account metadata.
  result = integrationEntries()
  result.add(provisionRequest(42, @[73'u8]))
  result.add(provisionRequest(99, @[81'u8]))

proc terminalProvisionExecution*(ending = TerminalProvisionEnding.Halt,
    checkpoint = true, second = true, first = true): AccumulationDispatchResult =
  ## Execute two authored provides around an optional checkpoint, then a real terminal instruction.
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 65536),
    registerImmediate(9, 1)]
  if first:
    instructions.add(@[10'u8, 28]) # Optional first contribution distinguishes empty, X-only and shared X/Y sets.
  if checkpoint:
    instructions.add(@[10'u8, 19]) # Snapshot only the first provision into exceptional effects.
  if second:
    instructions.add(registerImmediate(7, 99))
    instructions.add(registerImmediate(8, 196608))
    instructions.add(@[10'u8, 28]) # RW byte 81 belongs only to the newer regular context.
  case ending
  of TerminalProvisionEnding.Halt:
    discard # r8 holds a guest address, not the exactly-32-byte return length.
  of TerminalProvisionEnding.Panic:
    instructions.add(@[0'u8]) # A trap is completed guest panic, not a local refusal.
  of TerminalProvisionEnding.Fault:
    instructions.add(@[52'u8, 2, 0, 0, 4]) # Authored load from unmapped physical memory.
  of TerminalProvisionEnding.OutOfGas:
    instructions.add(@[10'u8, 28]) # Unknown host call costs 1000, funded below by only 999.
  of TerminalProvisionEnding.HashReturn:
    instructions.add(registerImmediate(7, 65536))
    instructions.add(registerImmediate(8, 32)) # Adopted #533 retains regular provisions alongside the returned hash.
  instructions.add(@[50'u8, 0]) # Halt is also the paid successor of a funded final host call.
  let extra = @[serviceMetadataEntry(ServiceIndex(99), default(ServiceMetadata), ByteLimit(
      ServiceMetadataBytes)).value,
    provisionRequest(42, @[73'u8]), provisionRequest(99, @[81'u8])]
  var prepared = guestProgram(instructions, 100000, extra = extra)
  if ending == TerminalProvisionEnding.OutOfGas:
    let price = uint64(blockGas(programOf(prepared.accumulationMachine.value).value,
      CodeAddress(5), GasCycleLimit(1000)).value)
    let credit = price+(if first: 3983'u64 else: 0'u64)+(if checkpoint: 103'u64 else: 0'u64)+(
        if second: 3983'u64 else: 0'u64)+999
    prepared = guestProgram(instructions, credit, extra = extra) # Every instruction cost is paid before the final host deficit.
  executeAccumulationMachine(prepared, pvmParameters(),
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1)), MemoryByteLimit(32),
    ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), pvmContextConfig(),
    provisionPolicy(items = 2, perBlob = 1, total = 2))
