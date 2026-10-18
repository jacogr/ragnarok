# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 implications: immutable yield replacement and regular-to-exceptional checkpoints.
## Exposes prepared effect pairs, dimension/source/metadata/yield extraction and state-only mutations.
## Guest memory, gas, registers, execution verdicts and publication belong to their caller's PVM layer.

import std/assertions
import ../codec/[composite, state_outputs]
import ./accumulation_context

type
  ## No refused/default operation exposes a partial context, fabricated hash or successful empty owner.
  AccumulationEffectError* {.pure.} = enum
    Uninitialized, None, InvalidContexts, InvalidDimension, YieldAbsent
  ## Only a present alternative stores a commitment; absence cannot expose a default all-zero hash.
  YieldValue = object
    case present: bool
    of true:
      commitment: OutputCommitment # Zero bytes remain a present protocol value.
    of false:
      discard                      # Absence carries no commitment payload.
  ## Current supported implications retain initial accounts/roles/next-ID with a replaceable yield.
  EffectData = ref object
    initial: InitialAccumulationContext
    output: YieldValue
  ## Read-only acyclic context; copies retain a version independently of later effect operations.
  AccumulationEffectContext* = object
    data: nil EffectData
  ## Private pair retains exact initial provenance; neither child refers back to this owner or older pairs.
  PairData = ref object
    source: PreparedAccumulationContexts
    regular, exceptional: AccumulationEffectContext
  ## Only prepared initial contexts create a pair; mutations preserve their service/input identity.
  AccumulationEffects* = object
    data: nil PairData
  ## Copied current facts distinguish incoming inputs from the still-empty outgoing effect sequences.
  AccumulationEffectInfo* = object
    service*, nextService*: ServiceIndex
    transfers*, provisions*: int
    hasYield*: bool
  ## Successful alternatives alone carry complete retained handles, facts or a present yield value.
  AccumulationEffectResult*[T] = object
    case status: AccumulationEffectError
    of None:
      completed: T # Contract-guarded extraction is the only public payload access.
    else:
      discard      # Refusals/defaults carry only their reason.

## Inspect success/failure without permitting retagging or mutable access.
func error*[T](outcome: AccumulationEffectResult[T]): AccumulationEffectError = outcome.status
## Extract selected success under compiler/runtime contracts, including optimized execution.
func value*[T](outcome: AccumulationEffectResult[T]): T {.inline,
    requires: outcome.status == AccumulationEffectError.None.} = outcome.completed

## Retain the exact initial context backing this version's accounts, roles, next-ID and input provenance.
proc effectInitialContext*(context: AccumulationEffectContext): AccumulationEffectResult[
    InitialAccumulationContext] =
  let data = context.data
  if data == nil:
    # A default effect cannot supply another context as a substitute source.
    return AccumulationEffectResult[InitialAccumulationContext](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[InitialAccumulationContext](status: AccumulationEffectError.None,
    completed: data.initial)

## Copy current yield-presence and retained service facts, never mutable implication storage.
proc effectInfo*(context: AccumulationEffectContext): AccumulationEffectResult[
    AccumulationEffectInfo] =
  let data = context.data
  if data == nil:
    # Missing owners cannot masquerade as valid services with zero effects.
    return AccumulationEffectResult[AccumulationEffectInfo](
        status: AccumulationEffectError.Uninitialized)
  let source = data.initial.contextInfo.value
  AccumulationEffectResult[AccumulationEffectInfo](status: AccumulationEffectError.None,
    completed: AccumulationEffectInfo(service: source.service, nextService: source.nextService,
      transfers: source.transfers, provisions: source.provisions, hasYield: data.output.present))

## Read a present yield by value; default and absent alternatives never return a fake zero commitment.
proc effectYield*(context: AccumulationEffectContext): AccumulationEffectResult[OutputCommitment] =
  let data = context.data
  if data == nil:
    # Default contexts have no selected yield state.
    return AccumulationEffectResult[OutputCommitment](status: AccumulationEffectError.Uninitialized)
  if not data.output.present:
    # A successfully prepared context may legitimately have no yield yet.
    return AccumulationEffectResult[OutputCommitment](status: AccumulationEffectError.YieldAbsent)
  AccumulationEffectResult[OutputCommitment](status: AccumulationEffectError.None,
    completed: data.output.commitment)

## Select one exact version; invalid enum casts cannot silently alias the exceptional dimension.
proc effectContext*(effects: AccumulationEffects, dimension: AccumulationDimension):
    AccumulationEffectResult[AccumulationEffectContext] =
  if ord(dimension) < ord(AccumulationDimension.Regular) or ord(dimension) > ord(
      AccumulationDimension.Exceptional):
    # Reject unsupported dimensions before selecting any retained child.
    return AccumulationEffectResult[AccumulationEffectContext](
        status: AccumulationEffectError.InvalidDimension)
  let data = effects.data
  if data == nil:
    # Default pairs are not initialized I squared values.
    return AccumulationEffectResult[AccumulationEffectContext](
        status: AccumulationEffectError.Uninitialized)
  let selected = if dimension == AccumulationDimension.Regular: data.regular
    else: data.exceptional # Only the two validated dimensions remain.
  AccumulationEffectResult[AccumulationEffectContext](status: AccumulationEffectError.None,
    completed: selected)

## Retain original prepared provenance independently of effect versions and checkpoint lifetimes.
proc effectsSource*(effects: AccumulationEffects): AccumulationEffectResult[
    PreparedAccumulationContexts] =
  let data = effects.data
  if data == nil:
    # No default pair may grant an initialized preparation certificate.
    return AccumulationEffectResult[PreparedAccumulationContexts](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[PreparedAccumulationContexts](status: AccumulationEffectError.None,
    completed: data.source)

## Begin at the actual initial I in both dimensions; no caller-selected replacement state or yield is accepted.
proc prepareAccumulationEffects*(contexts: PreparedAccumulationContexts): AccumulationEffectResult[
    AccumulationEffects] =
  let initial = contexts.initialContext(AccumulationDimension.Regular)
  if initial.error != AccumulationContextError.None:
    # Only successfully prepared immutable contexts can authorize host state effects.
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.InvalidContexts)
  let current = AccumulationEffectContext(data: EffectData(initial: initial.value,
    output: YieldValue(present: false)))
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: contexts, regular: current,
        exceptional: current)))

## Apply only the state part of a validated yield call: replace regular yield, preserving the checkpoint.
## The host dispatcher must first charge gas/read guest memory; failures there must not call this operation.
proc recordAccumulationYield*(effects: AccumulationEffects, commitment: OutputCommitment):
    AccumulationEffectResult[AccumulationEffects] =
  let data = effects.data
  if data == nil:
    # Refuse before constructing a partially initialized regular context.
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.Uninitialized)
  let previous = data.regular.data
  assert previous != nil # Private construction preserves initialized children for every published pair.
  let current = AccumulationEffectContext(data: EffectData(initial: previous.initial,
    output: YieldValue(present: true, commitment: commitment)))
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

## Apply only checkpoint's implication assignment Y'=X; later regular changes cannot alter the retained snapshot.
## Guest gas/r7 handling is outside this state-only operation; no implicit checkpoint occurs on yield.
proc checkpointAccumulationEffects*(effects: AccumulationEffects): AccumulationEffectResult[
    AccumulationEffects] =
  let data = effects.data
  if data == nil:
    # A checkpoint cannot turn an uninitialized pair into successful empty implications.
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: data.regular,
      exceptional: data.regular)))
