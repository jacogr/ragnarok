# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 host 8 appends padded export segments to an immutable invocation-local successor.
## Exposes bounded append responses and copied segment access; no invocation authentication or publication.

import std/assertions
import ./[machine, step]
import ./host/fetch as host_fetch
import ../codec/bounded
import ../codec/work/digest as work_digest

type
  ExportOffset* = distinct uint64 ## Package segment position before this invocation's ordered exports.
  RefinementExportError* {.pure.} = enum ## Local refusals never fabricate a charged guest reply or export successor.
    Uninitialized, None, InvalidContext, InvalidMemory, LimitExceeded
  ExportLimits* = object ## Local caps cover all segments retained by the new successor, not just this call's input.
    items*: ElementLimit
    bytes*: ByteLimit
  SegmentData = ref object ## Immutable fixed segment storage may be shared by acyclic successor owners.
    bytes: FetchSegment
  ExportData = ref object ## Ordered immutable references avoid recopying prior segment payloads on append.
    offset: ExportOffset
    segments: seq[SegmentData]
  RefinementExports* = object ## Default is invalid; explicit capture starts with an empty export sequence.
    data: nil ExportData
  ExportTransition* = object ## A completed protocol response retains its matching immutable export successor.
    response*: HostResponse
    exports*: RefinementExports
  RefinementExportResult* = object ## Private alternatives prevent default/refused success extraction.
    case status: RefinementExportError
    of None:
      completed: ExportTransition
    else:
      discard # No partial owner or charged reply escapes local refusal.

func error*(outcome: RefinementExportResult): RefinementExportError =
  ## Inspect the reason without exposing a writable discriminator.
  outcome.status
func value*(outcome: RefinementExportResult): ExportTransition
    {.requires: outcome.status == RefinementExportError.None.} =
  ## Extract only a completed response/successor pair.
  outcome.completed
proc captureRefinementExports*(offset: ExportOffset): RefinementExports =
  ## Retain the caller's full-width package offset with an explicitly empty ordered sequence.
  RefinementExports(data: ExportData(offset: offset, segments: @[]))
proc count*(exports: RefinementExports): ExportCount {.requires: exports.data != nil.} =
  ## Inspect only initialized immutable export owners.
  let data = exports.data
  assert data != nil # Retain the checked owner for compiler flow analysis.
  ExportCount(uint64(data.segments.len))
proc segment*(exports: RefinementExports, index: ExportCount): FetchSegment
    {.requires: exports.data != nil and uint64(index) < uint64(exports.data.segments.len).} =
  ## Return an independent fixed-size value; no mutable storage view escapes the owner.
  let data = exports.data
  assert data != nil # The public precondition rejects a default owner.
  data.segments[int(uint64(index))].bytes

proc exportResponse*(exports: RefinementExports, gas: MachineGas, registers: RegisterFile,
    memory: Memory, limits: ExportLimits): RefinementExportResult =
  ## Evaluate Omega_E; the dispatcher separately selects host 8 and applies the returned pair atomically.
  let data = exports.data
  if data == nil:
    return RefinementExportResult(status: RefinementExportError.InvalidContext) # Never promote a missing owner to empty.
  if memory.pageImage(PageIndex(0)).error != MachineError.None:
    return RefinementExportResult(status: RefinementExportError.InvalidMemory) # A local owner defect is not guest panic.
  var transition = ExportTransition(exports: exports,
    response: HostResponse(action: HostAction.Continue, gas: MachineGas(0), gasDeficit: GasDeficit(0),
      registers: registers, memory: memory))
  let credit = uint64(gas)
  if credit < 3521:
    transition.response.action = HostAction.OutOfGas
    transition.response.gasDeficit = GasDeficit(0) # Zero-gas OutOfGas precedes memory and capacity checks.
    return RefinementExportResult(status: RefinementExportError.None, completed: transition)
  transition.response.gas = MachineGas(credit-3521)
  let size = min(uint64(registers[8]), 4104'u64)
  let input = readBytes(memory, MemoryAddress(uint64(registers[7])), MemoryLength(size),
      MemoryByteLimit(4104))
  case input.error
  of MachineError.None:
    discard # Even protocol-full contexts must first validate the complete selected input.
  of MachineError.Fault, MachineError.InvalidRange:
    transition.response.action = HostAction.Panic
    return RefinementExportResult(status: RefinementExportError.None, completed: transition)
  else:
    return RefinementExportResult(status: RefinementExportError.InvalidMemory) # The fixed read has no variable local cap.
  let offset = uint64(data.offset)
  let count = uint64(data.segments.len)
  if offset >= 3072 or count >= 3072-offset:
    transition.response.registers[7] = RegisterValue(high(uint64)-4) # FULL cannot overflow the package index.
    return RefinementExportResult(status: RefinementExportError.None, completed: transition)
  let next = count+1 # The preceding capacity bound proves next<=3072 and next*4104 fits every supported host int.
  if next > uint64(limits.items) or next*4104 > uint64(limits.bytes):
    return RefinementExportResult(status: RefinementExportError.LimitExceeded) # Local refusal is distinct from protocol FULL.
  var bytes = default(array[4104, byte])
  for index in 0..<input.value.len:
    bytes[index] = input.value[index] # The initialized tail remains zero; clipped input is at most one segment.
  var segments = newSeqOfCap[SegmentData](int(next))
  for index in 0..<data.segments.len:
    segments.add(data.segments[index]) # Share immutable payloads, never the mutable sequence metadata.
  segments.add(SegmentData(bytes: FetchSegment(bytes)))
  transition.exports = RefinementExports(data: ExportData(offset: data.offset, segments: segments))
  transition.response.registers[7] = RegisterValue(
      offset+count) # Capacity proved the index below 3072 before addition.
  RefinementExportResult(status: RefinementExportError.None, completed: transition)
