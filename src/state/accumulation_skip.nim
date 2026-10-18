# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 Psi_A code-unavailable/oversized alternative for transfer-free initial invocations.
## Exposes immutable zero-gas/empty-effect outcomes and pure/block-bound source extraction; never executes or writes.

import ../codec/[composite, header, work_digest]
import ./[accumulation_service, store]

type
  ## A refusal cannot expose a completed no-execution outcome or silently swallow a service preparation error.
  AccumulationSkipError* {.pure.} = enum
    Uninitialized, None, InvalidService, ExecutionRequired
  ## Copied initial-round outcome facts; all effects are empty and gas usage is zero by construction.
  AccumulationSkipInfo* = object
    service*: ServiceIndex
    slot*: HeaderSlot
    code*: AccumulationCodeStatus
    gasUsed*: Gas
    transfers*, provisions*: int
    hasYield*: bool
  ## Private acyclic storage retains the original resolved service, inputs and complete immutable source map.
  SkipData = ref object
    service: PreparedAccumulationService
  ## Only certified unavailable/oversized code can construct this complete non-executing outcome.
  SkippedAccumulation* = object
    data: nil SkipData
  ## Private bound storage retains both genuine block provenance and its pure no-execution outcome.
  BlockSkipData = ref object
    service: BlockAccumulationService
    projection: SkippedAccumulation
  ## Only the block adapter constructs this initial-round outcome from a genuine bound service.
  BlockSkippedAccumulation* = object
    data: nil BlockSkipData
  ## Default/refused alternatives contain reasons alone, never fabricated successful empty effects.
  AccumulationSkipResult*[T] = object
    case status: AccumulationSkipError
    of None:
      completed: T # Complete certified outcomes alone carry retained state.
    else:
      discard      # No success payload accompanies preparation refusal or required execution.

## Inspect a refusal without permitting result retagging.
func error*[T](outcome: AccumulationSkipResult[T]): AccumulationSkipError = outcome.status
## Extract selected success under supported compiler/runtime contracts, including optimized builds.
func value*[T](outcome: AccumulationSkipResult[T]): T {.inline,
    requires: outcome.status == AccumulationSkipError.None.} = outcome.completed

## Copy the exact skip reason and protocol zero/empty effects, without changing account timestamps or balance.
proc skipInfo*(outcome: SkippedAccumulation): AccumulationSkipResult[AccumulationSkipInfo] =
  let data = outcome.data
  if data == nil: return AccumulationSkipResult[AccumulationSkipInfo](
    status: AccumulationSkipError.Uninitialized) # No default successful outcome.
  let source = data.service.serviceInfo.value
  AccumulationSkipResult[AccumulationSkipInfo](status: AccumulationSkipError.None,
    completed: AccumulationSkipInfo(service: source.service, slot: source.slot, code: source.code,
      gasUsed: Gas(0), transfers: 0, provisions: 0, hasYield: false))

## Retain the exact complete source map; with no incoming transfers, Psi_A's post-transfer state is unchanged.
## This neither filters account namespaces nor newly validates unrelated chapters or computes a partial root.
proc skipState*(outcome: SkippedAccumulation): AccumulationSkipResult[StateStoreSnapshot] =
  let data = outcome.data
  if data == nil: return AccumulationSkipResult[StateStoreSnapshot](
    status: AccumulationSkipError.Uninitialized) # Default owners cannot supply fake empty state.
  AccumulationSkipResult[StateStoreSnapshot](status: AccumulationSkipError.None,
    completed: data.service.serviceState.value)

## Retain the resolved input/account/code-status provenance independently of the skipped outcome handle.
proc skipService*(outcome: SkippedAccumulation): AccumulationSkipResult[
    PreparedAccumulationService] =
  let data = outcome.data
  if data == nil: return AccumulationSkipResult[PreparedAccumulationService](
    status: AccumulationSkipError.Uninitialized) # No substitute service certificate.
  AccumulationSkipResult[PreparedAccumulationService](status: AccumulationSkipError.None,
    completed: data.service)

## Complete only Psi_A's non-executing alternative; Ready, including empty code, requires real PVM dispatch.
## Service preparation already proved code identity/envelope/size and explicitly refused incoming transfers.
proc finishUninvokedAccumulation*(service: PreparedAccumulationService): AccumulationSkipResult[
    SkippedAccumulation] =
  let info = service.serviceInfo
  if info.error != AccumulationServiceError.None:
    return AccumulationSkipResult[SkippedAccumulation](
      status: AccumulationSkipError.InvalidService) # Missing accounts, corrupt state and backend/resource failures cannot be passed as successful owners.
  if info.value.transfers != 0:
    return AccumulationSkipResult[SkippedAccumulation](
      status: AccumulationSkipError.InvalidService) # Do not discard future transfer credit if upstream preparation expands.
  case info.value.code
  of AccumulationCodeStatus.Ready:
    AccumulationSkipResult[SkippedAccumulation](
      status: AccumulationSkipError.ExecutionRequired) # No zero-length shortcut or fabricated invalid-program outcome.
  of AccumulationCodeStatus.Missing, AccumulationCodeStatus.Malformed,
      AccumulationCodeStatus.Oversized:
    AccumulationSkipResult[SkippedAccumulation](status: AccumulationSkipError.None,
      completed: SkippedAccumulation(data: SkipData(
          service: service))) # Only the three certified non-executing reasons complete.

## Retain the genuine initial-round service certificate without replacing its block or parent map.
proc skipBlockService*(outcome: BlockSkippedAccumulation): AccumulationSkipResult[
    BlockAccumulationService] =
  let data = outcome.data
  if data == nil: return AccumulationSkipResult[BlockAccumulationService](
    status: AccumulationSkipError.Uninitialized) # No forged block-bound service.
  AccumulationSkipResult[BlockAccumulationService](status: AccumulationSkipError.None,
    completed: data.service)

## Extract the pure complete no-execution projection while retaining immutable source ownership.
proc skipProjection*(outcome: BlockSkippedAccumulation): AccumulationSkipResult[
    SkippedAccumulation] =
  let data = outcome.data
  if data == nil: return AccumulationSkipResult[SkippedAccumulation](
    status: AccumulationSkipError.Uninitialized) # No default outcome masquerades as skipped success.
  AccumulationSkipResult[SkippedAccumulation](status: AccumulationSkipError.None,
    completed: data.projection)

## Complete the code gate from an actual bound service; no entropy lookup, I construction or state writes occur.
proc finishBlockUninvokedAccumulation*(service: BlockAccumulationService): AccumulationSkipResult[
    BlockSkippedAccumulation] =
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
