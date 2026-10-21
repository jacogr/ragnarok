# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine authored transfer executions provide terminal-selected collection fixtures without forging outcomes.

import std/assertions
import ../../src/chain/parameters
import ../../src/state/[accumulation_dispatch, accumulation_outcome, accumulation_transfers]
import ../../src/codec/[bounded, composite, state_accounts]
import ../../src/pvm/[machine, program, gas, step, host_fetch]
import ./[pvm_accumulation_context, pvm_accumulation_program]

type
  TransferEnding* {.pure.} = enum ## Each choice runs an actual guest terminal instruction.
    Halt, Panic, Fault, OutOfGas, HashReturn

proc collectionLimits*(sources = 3'u64, transfers = 6'u64, memoBytes = 768'u64):
    AccumulationTransferCollectionLimits =
  ## Independent caller ceilings make exact boundaries explicit in collection witnesses.
  AccumulationTransferCollectionLimits(sources: ElementLimit(sources),
    transfers: ElementLimit(transfers), memoBytes: ByteLimit(memoBytes))

proc transferParameters(): Parameters =
  ## Literal parameter offsets provide a funded 10-unit account threshold and the exact 128-byte memo profile.
  var bytes = encodeParameters(pvmParameters())
  for index in 0..<24:
    bytes[index] = 0 # Zero item/byte deposits and initialize the complete base-deposit word.
  bytes[16] = 10
  bytes[24] = 2
  bytes[25] = 0
  bytes[82] = 80
  bytes[83] = 0
  for index in 110..<114:
    bytes[index] = 0 # Initialize the full E4 memo-width field before setting its bounded literal value.
  bytes[110] = 128
  decodeParameters(bytes).value

proc transferExecution*(ending = TransferEnding.Halt, checkpoint = true,
    second = true, duplicate = false, service = 42'u32, offeredGas = 0'u64, credit = 100000'u64):
    AccumulationDispatchResult =
  ## Append a self transfer, optionally checkpoint, append again and reach the requested terminal path.
  var memo = newSeq[byte](128)
  for index in 0..<128:
    memo[index] = byte((index*7+3) mod 256) # Raw opaque memo contains zero and non-ASCII bytes.
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, uint64(service)),
    @[51'u8, 9, 0], registerImmediate(10, 5), registerImmediate(11, offeredGas),
    registerImmediate(12, 196608), @[10'u8, 22]]
  if checkpoint:
    instructions.add(@[10'u8, 19]) # Only the first transfer and debit belong to Y.
  if second:
    instructions.add(registerImmediate(7, high(uint64)))
    if not duplicate:
      instructions.add(registerImmediate(10, 0))
      instructions.add(registerImmediate(12, 65536)) # Zero self-transfer with a distinct read-only memo.
    instructions.add(@[10'u8, 22]) # Duplicate mode preserves amount, gas and memo exactly.
  case ending
  of TransferEnding.Halt:
    discard # Ordinary halt keeps the newer regular sequence.
  of TransferEnding.Panic:
    instructions.add(@[0'u8]) # Actual trap selects exceptional effects.
  of TransferEnding.Fault:
    instructions.add(@[52'u8, 2, 0, 0, 4]) # Unmapped load normalizes to panic and selects Y.
  of TransferEnding.OutOfGas:
    instructions.add(@[10'u8, 30]) # A final unknown call costs 1000, funded with only 999.
  of TransferEnding.HashReturn:
    instructions.add(registerImmediate(7, 65536))
    instructions.add(registerImmediate(8, 32)) # Readable hash return keeps X's outgoing transfers.
  instructions.add(@[50'u8, 0])
  let account = ServiceMetadata(balance: AccountBalance(100))
  var prepared = guestProgram(instructions, credit, account = account, writable = memo,
    service = ServiceIndex(service))
  if ending == TransferEnding.OutOfGas:
    assert offeredGas <= 100000 # Prove this test-only credit sum and multiplication cannot wrap.
    let price = uint64(blockGas(programOf(prepared.accumulationMachine.value).value,
      CodeAddress(5), GasCycleLimit(1000)).value)
    let credit = price+(575+offeredGas)*(if second: 2'u64 else: 1'u64) +
      (if checkpoint: 103'u64 else: 0'u64)+999
    prepared = guestProgram(instructions, credit, account = account, writable = memo,
      service = ServiceIndex(service)) # Small authored gas values keep this fixture calculation bounded.
  executeAccumulationMachine(prepared, transferParameters(),
    FetchAccumulationLimits(items: ElementLimit(0), bytes: ByteLimit(1)), MemoryByteLimit(128),
    ExecutionStepLimit(100), HostCallLimit(10), GasCycleLimit(1000), pvmContextConfig(),
    transferLimit = ElementLimit(2))

proc transferOutcome*(ending = TransferEnding.Halt, checkpoint = true,
    second = true, duplicate = false, service = 42'u32): AccumulationOutcome =
  ## Retain only the completed dispatch's own normalized result after local execution storage is released.
  normalizeAccumulationOutcome(transferExecution(ending, checkpoint, second, duplicate,
      service)).value
