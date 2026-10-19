# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 Psi_A code-unavailable/oversized alternative after incoming transfer credit.
## Exposes immutable zero-gas/empty-effect outcomes and pure/block-bound source extraction; never executes or republishes credit.

import ../codec/[composite, header, work_digest]
import ./[accumulation_service, store]

type
  AccumulationSkipError* {.pure.} = enum ## A refusal cannot expose a completed no-execution outcome or silently swallow a service preparation error.
    Uninitialized, None, InvalidService, ExecutionRequired
  AccumulationSkipInfo* = object ## Copied initial-round outcome facts; all effects are empty and gas usage is zero by construction.
    service*: ServiceIndex
    slot*: HeaderSlot
    code*: AccumulationCodeStatus
    gasUsed*: Gas
    transfers*, provisions*: int
    hasYield*: bool
  ## Private acyclic storage retains the original resolved service, inputs and complete immutable source map.
  SkipData = ref object
    service: PreparedAccumulationService
  SkippedAccumulation* = object ## Only certified unavailable/oversized code can construct this complete non-executing outcome.
    data: nil SkipData
  ## Private bound storage retains both genuine block provenance and its pure no-execution outcome.
  BlockSkipData = ref object
    service: BlockAccumulationService
    projection: SkippedAccumulation
  BlockSkippedAccumulation* = object ## Only the block adapter constructs this initial-round outcome from a genuine bound service.
    data: nil BlockSkipData
  AccumulationSkipResult*[T] = object ## Default/refused alternatives contain reasons alone, never fabricated successful empty effects.
    case status: AccumulationSkipError
    of None:
      completed: T # Complete certified outcomes alone carry retained state.
    else:
      discard      # No success payload accompanies preparation refusal or required execution.

func error*[T](outcome: AccumulationSkipResult[T]): AccumulationSkipError =
  ## Inspect a refusal without permitting result retagging.
  outcome.status
func value*[T](outcome: AccumulationSkipResult[T]): T {.inline,
    requires: outcome.status == AccumulationSkipError.None.} =
  ## Extract selected success under supported compiler/runtime contracts, including optimized builds.
  outcome.completed

proc skipInfo*(outcome: SkippedAccumulation): AccumulationSkipResult[AccumulationSkipInfo] =
  ## Copy the exact skip reason and protocol zero/empty effects, without further changing the already credited account.
  let data = outcome.data
  if data == nil: return AccumulationSkipResult[AccumulationSkipInfo](
    status: AccumulationSkipError.Uninitialized) # No default successful outcome.
  let source = data.service.serviceInfo.value
  AccumulationSkipResult[AccumulationSkipInfo](status: AccumulationSkipError.None,
    completed: AccumulationSkipInfo(service: source.service, slot: source.slot, code: source.code,
      gasUsed: Gas(0), transfers: 0, provisions: 0, hasYield: false))

proc skipState*(outcome: SkippedAccumulation): AccumulationSkipResult[StateStoreSnapshot] =
  ## Retain the complete post-transfer map, including credit even when no code executes.
  ## This neither filters account namespaces nor newly validates unrelated chapters or computes a partial root.
  let data = outcome.data
  if data == nil: return AccumulationSkipResult[StateStoreSnapshot](
    status: AccumulationSkipError.Uninitialized) # Default owners cannot supply fake empty state.
  AccumulationSkipResult[StateStoreSnapshot](status: AccumulationSkipError.None,
    completed: data.service.serviceState.value)

proc skipService*(outcome: SkippedAccumulation): AccumulationSkipResult[
    PreparedAccumulationService] =
  ## Retain the resolved input/account/code-status provenance independently of the skipped outcome handle.
  let data = outcome.data
  if data == nil: return AccumulationSkipResult[PreparedAccumulationService](
    status: AccumulationSkipError.Uninitialized) # No substitute service certificate.
  AccumulationSkipResult[PreparedAccumulationService](status: AccumulationSkipError.None,
    completed: data.service)

proc finishUninvokedAccumulation*(service: PreparedAccumulationService): AccumulationSkipResult[
    SkippedAccumulation] =
  ## Complete only Psi_A's non-executing alternative; Ready, including empty code, requires real PVM dispatch.
  ## Service preparation already proved code identity/envelope/size and retained incoming transfer credit.
  let info = service.serviceInfo
  if info.error != AccumulationServiceError.None:
    return AccumulationSkipResult[SkippedAccumulation](
      status: AccumulationSkipError.InvalidService) # Missing accounts, corrupt state and backend/resource failures cannot be passed as successful owners.
  case info.value.code
  of AccumulationCodeStatus.Ready:
    AccumulationSkipResult[SkippedAccumulation](
      status: AccumulationSkipError.ExecutionRequired) # No zero-length shortcut or fabricated invalid-program outcome.
  of AccumulationCodeStatus.Missing, AccumulationCodeStatus.Malformed,
      AccumulationCodeStatus.Oversized:
    AccumulationSkipResult[SkippedAccumulation](status: AccumulationSkipError.None,
      completed: SkippedAccumulation(data: SkipData(
          service: service))) # Only the three certified non-executing reasons complete.

proc skipBlockService*(outcome: BlockSkippedAccumulation): AccumulationSkipResult[
    BlockAccumulationService] =
  ## Retain the genuine initial-round service certificate without replacing its block or parent map.
  let data = outcome.data
  if data == nil: return AccumulationSkipResult[BlockAccumulationService](
    status: AccumulationSkipError.Uninitialized) # No forged block-bound service.
  AccumulationSkipResult[BlockAccumulationService](status: AccumulationSkipError.None,
    completed: data.service)

proc skipProjection*(outcome: BlockSkippedAccumulation): AccumulationSkipResult[
    SkippedAccumulation] =
  ## Extract the pure complete no-execution projection while retaining immutable source ownership.
  let data = outcome.data
  if data == nil: return AccumulationSkipResult[SkippedAccumulation](
    status: AccumulationSkipError.Uninitialized) # No default outcome masquerades as skipped success.
  AccumulationSkipResult[SkippedAccumulation](status: AccumulationSkipError.None,
    completed: data.projection)

proc finishBlockUninvokedAccumulation*(service: BlockAccumulationService): AccumulationSkipResult[
    BlockSkippedAccumulation] =
  ## Complete the code gate from an actual bound service; no entropy lookup, I construction or state writes occur.
  let projected = service.serviceProjection
  if projected.error != AccumulationServiceError.None:
    return AccumulationSkipResult[BlockSkippedAccumulation](
      status: AccumulationSkipError.InvalidService) # Only a genuine certificate can expose an initial-round source.
  let completed = finishUninvokedAccumulation(projected.value)
  if completed.error != AccumulationSkipError.None:
    return AccumulationSkipResult[BlockSkippedAccumulation](
      status: completed.error) # Preserve required execution and preparation refusal, without a partial bound owner.
  AccumulationSkipResult[BlockSkippedAccumulation](status: AccumulationSkipError.None,
    completed: BlockSkippedAccumulation(data: BlockSkipData(service: service,
      projection: completed.value)))
