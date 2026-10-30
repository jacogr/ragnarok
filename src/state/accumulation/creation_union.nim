# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current accpar n: immutable final prior-absent accounts from genuine nonannulled producers.
## This certificate selects logical accounts; physical publication and complete block coverage remain separate.
import std/[algorithm, assertions]
import ../../codec/bounded
import ../../codec/state/[accounts as state_accounts, layout as state_layout]
import ./[annulment as accumulation_annulment, outcome as accumulation_outcome,
    effects as accumulation_effects]
import ../store

type
  AccumulationCreationIndex* = distinct uint64 ## Final new-account ordinal is distinct from original producer or fact ordinals.
  AccumulationCreationLimits* = object ## Every original producer, enabled fact and selected account has an independent ceiling.
    outcomes*, creations*, accounts*, checks*: ElementLimit
  AccumulationCreationInfo* = object ## Copied traversal counts do not imply complete publication or block validity.
    outcomes*, creations*, accounts*: int
    checks*: uint64
  AccumulationCreationEntry* = object ## Fixed copied identities cannot forge an immutable selected account.
    service*, producer*: ServiceIndex
  AccumulationCreationError* {.pure.} = enum ## Refused/default alternatives carry only a typed reason.
    Uninitialized, None, InvalidSource, IncompleteFacts, InvalidState, MalformedState,
    LimitExceeded, Collision, InvalidIndex
  CreationRow = object # Immutable final values belong to the exact producing context retained by source.
    entry: AccumulationCreationEntry
    original: int
    accounts: StateStoreSnapshot
    metadata: ServiceMetadata
  CreationData = ref object # Acyclic source ownership retains no borrowed arrays or mutable exported buffers.
    source: PreparedAccumulationAnnulment
    rows: seq[CreationRow]
    info: AccumulationCreationInfo
  PreparedAccumulationCreationUnion* = object ## Only complete checked selection constructs this certificate.
    data: nil CreationData
  AccumulationCreationResult*[T] = object ## Success-only guarded extraction prevents partial/default payloads.
    case status: AccumulationCreationError
    of None:
      completed: T # No public writable discriminator or inactive success storage.
    else:
      discard      # Failure carries its reason alone.

func error*[T](outcome: AccumulationCreationResult[T]): AccumulationCreationError =
  ## Inspect the reason without granting result mutation.
  outcome.status

func value*[T](outcome: AccumulationCreationResult[T]): T {.inline,
    requires: outcome.status == AccumulationCreationError.None.} =
  ## Extract only a complete selected success under optimized checked contracts.
  outcome.completed

func compareRows(left, right: CreationRow): int =
  ## Unique protocol IDs sort numerically, independently of original arrival order.
  if uint32(left.entry.service) < uint32(right.entry.service): return -1 # Lower service first.
  if uint32(left.entry.service) > uint32(right.entry.service): return 1 # Higher service follows.
  0

proc prepareAccumulationCreationUnion*(source: PreparedAccumulationAnnulment,
    limits: AccumulationCreationLimits): AccumulationCreationResult[
        PreparedAccumulationCreationUnion] =
  ## Select final n membership from enabled actual creation facts, refusing cross-producer conflicts atomically.
  template fail(reason: AccumulationCreationError) =
    return AccumulationCreationResult[PreparedAccumulationCreationUnion](status: reason)
  let facts = source.annulmentInfo
  if facts.error != AccumulationAnnulmentError.None:
    fail(AccumulationCreationError.InvalidSource) # No caller-authored cancellation flags.
  if uint64(facts.value.outcomes) > uint64(limits.outcomes):
    fail(AccumulationCreationError.LimitExceeded) # Bound original producer traversal first.
  let prior = source.annulmentPrior.value
  var work = 0'u64
  var inspected = 0'u64
  var rows: seq[CreationRow] = @[]
  template spend() =
    if work >= uint64(limits.checks): fail(AccumulationCreationError.LimitExceeded)
    inc work # Every source/fact/membership comparison is charged before its bounded access.
  for index in 0..<facts.value.outcomes:
    spend()
    let decision = source.annulmentDecisionAt(AccumulationAnnulmentIndex(uint64(index))).value
    if decision.annulled: continue # N clears the complete account contribution, including raw creation history.
    let original = source.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(uint64(index))).value
    let context = original.outcomeContext.value
    let count = context.effectCreatedAccountFactCount
    if count.error != AccumulationEffectError.None:
      fail(AccumulationCreationError.IncompleteFacts) # Disabled tracking cannot certify an empty final creation set.
    if uint64(count.value) > uint64(limits.creations)-inspected:
      fail(AccumulationCreationError.LimitExceeded) # Prove aggregate addition before tracing any fact from this producer.
    inspected += uint64(count.value)
    let accounts = context.effectAccounts.value
    for ordinal in 0..<count.value:
      spend()
      let child = context.effectCreatedAccountFactAt(AccumulationCreatedAccountIndex(uint64(
          ordinal))).value
      let key = chapterServiceKey(StateChapter(255), child.service)
      let previous = prior.lookup(key)
      if previous.error == StateStoreError.None:
        if previous.value.byteLength != ServiceMetadataBytes:
          fail(AccumulationCreationError.MalformedState) # Prior-present membership is never repaired by n.
        continue # A prior ID, including an actual recreation, belongs to M rather than n.
      if previous.error != StateStoreError.MissingKey:
        fail(AccumulationCreationError.InvalidState) # Invalid prior lookup cannot establish absence.
      spend()
      let final = accounts.lookup(key)
      if final.error == StateStoreError.MissingKey: continue # n uses final presence, not historical birth alone.
      if final.error != StateStoreError.None:
        fail(AccumulationCreationError.InvalidState) # No default or invalid account owner escapes.
      if final.value.byteLength != ServiceMetadataBytes:
        fail(AccumulationCreationError.MalformedState) # Bound metadata copying by the exact canonical extent.
      let decoded = decodeServiceMetadata(final.value.bytes, ByteLimit(ServiceMetadataBytes))
      if decoded.error != ServiceMetadataError.None:
        fail(AccumulationCreationError.MalformedState) # Refuse noncanonical final account values.
      var duplicate = false
      for earlier in rows:
        spend()
        if uint32(earlier.entry.service) == uint32(child.service):
          if earlier.original != index:
            fail(AccumulationCreationError.Collision) # Distinct producers may not contribute one new ID, even equal values.
          duplicate = true # Multiple facts in one final source map still identify one logical account.
          break
      if duplicate: continue # Do not duplicate a producer's final account.
      if uint64(rows.len) >= uint64(limits.accounts) or rows.len >= high(int) div sizeof(CreationRow):
        fail(AccumulationCreationError.LimitExceeded) # Bound native descriptor growth before allocation.
      rows.add(CreationRow(entry: AccumulationCreationEntry(service: child.service,
        producer: decision.service), original: index, accounts: accounts,
        metadata: decoded.value.metadata))
  if inspected > uint64(high(int)):
    fail(AccumulationCreationError.LimitExceeded) # Public copied counts must fit their native domain.
  rows.sort(compareRows) # Unique final IDs and bounded row count make canonical ordering deterministic.
  AccumulationCreationResult[PreparedAccumulationCreationUnion](
    status: AccumulationCreationError.None,
    completed: PreparedAccumulationCreationUnion(data: CreationData(source: source, rows: rows,
      info: AccumulationCreationInfo(outcomes: facts.value.outcomes, creations: int(inspected),
        accounts: rows.len, checks: work))))

proc creationUnionInfo*(plan: PreparedAccumulationCreationUnion): AccumulationCreationResult[
    AccumulationCreationInfo] =
  ## Copy bounded selection facts without exposing retained arrays.
  let data = plan.data
  if data == nil: return AccumulationCreationResult[AccumulationCreationInfo](
      status: AccumulationCreationError.Uninitialized) # No default empty union.
  AccumulationCreationResult[AccumulationCreationInfo](status: AccumulationCreationError.None,
      completed: data.info)

proc creationUnionSource*(plan: PreparedAccumulationCreationUnion): AccumulationCreationResult[
    PreparedAccumulationAnnulment] =
  ## Retain the exact genuine cancellation/source proof.
  let data = plan.data
  if data == nil: return AccumulationCreationResult[PreparedAccumulationAnnulment](
      status: AccumulationCreationError.Uninitialized) # No substitute prior/outcomes.
  AccumulationCreationResult[PreparedAccumulationAnnulment](status: AccumulationCreationError.None,
      completed: data.source)

proc checkedRow(plan: PreparedAccumulationCreationUnion,
    index: AccumulationCreationIndex): AccumulationCreationResult[CreationRow] =
  ## Private same-owner validation precedes full-width narrowing for every account accessor.
  let data = plan.data
  if data == nil: return AccumulationCreationResult[CreationRow](
      status: AccumulationCreationError.Uninitialized) # No fabricated selected row.
  if uint64(index) >= uint64(data.rows.len): return AccumulationCreationResult[CreationRow](
      status: AccumulationCreationError.InvalidIndex) # Upper bits cannot alias a valid account.
  AccumulationCreationResult[CreationRow](status: AccumulationCreationError.None,
      completed: data.rows[int(uint64(index))])

proc createdAccountAt*(plan: PreparedAccumulationCreationUnion,
    index: AccumulationCreationIndex): AccumulationCreationResult[AccumulationCreationEntry] =
  ## Copy protocol account and original producer identities.
  let row = checkedRow(plan, index)
  if row.error != AccumulationCreationError.None: return AccumulationCreationResult[
      AccumulationCreationEntry](status: row.error) # Preserve same-owner refusal.
  AccumulationCreationResult[AccumulationCreationEntry](status: AccumulationCreationError.None,
      completed: row.value.entry)

proc createdAccountMetadataAt*(plan: PreparedAccumulationCreationUnion,
    index: AccumulationCreationIndex): AccumulationCreationResult[ServiceMetadata] =
  ## Copy canonical metadata from the exact final producing map.
  let row = checkedRow(plan, index)
  if row.error != AccumulationCreationError.None: return AccumulationCreationResult[
      ServiceMetadata](status: row.error) # No inactive metadata extraction.
  AccumulationCreationResult[ServiceMetadata](status: AccumulationCreationError.None,
      completed: row.value.metadata)

proc createdAccountSnapshotAt*(plan: PreparedAccumulationCreationUnion,
    index: AccumulationCreationIndex): AccumulationCreationResult[StateStoreSnapshot] =
  ## Retain the complete source snapshot scoped to this logical account; it is not a merged batch root.
  let row = checkedRow(plan, index)
  if row.error != AccumulationCreationError.None: return AccumulationCreationResult[
      StateStoreSnapshot](status: row.error) # No fabricated final map.
  AccumulationCreationResult[StateStoreSnapshot](status: AccumulationCreationError.None,
      completed: row.value.accounts)

proc createdAccountOutcomeAt*(plan: PreparedAccumulationCreationUnion,
    index: AccumulationCreationIndex): AccumulationCreationResult[AccumulationOutcome] =
  ## Retain the actual surviving original outcome that contributed this new account.
  let row = checkedRow(plan, index)
  if row.error != AccumulationCreationError.None: return AccumulationCreationResult[
      AccumulationOutcome](status: row.error) # No fabricated execution result.
  let data = plan.data
  assert data != nil # Same immutable owner was established by checkedRow.
  let original = data.source.annulmentOriginalOutcomeAt(AccumulationAnnulmentIndex(uint64(
      row.value.original))).value
  AccumulationCreationResult[AccumulationOutcome](status: AccumulationCreationError.None,
      completed: original)
