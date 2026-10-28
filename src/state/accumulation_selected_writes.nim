# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded physical writes for an exact-source selected prior-account subset M and new-account union n.
## Retained complete snapshots authorize only the selected logical accounts; this plan does not publish state.
import ../codec/bounded as codec_bounded
import ../codec/state_accounts as codec_state_accounts
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
import ./accumulation_annulment as state_accumulation_annulment
import ./accumulation_account_selection as state_accumulation_account_selection
import ./accumulation_creation_union as state_accumulation_creation_union
import ./accumulation_outcome as state_accumulation_outcome
import ./accumulation_effects as state_accumulation_effects
import ./store as state_store

type
  AccumulationSelectedWriteIndex* = distinct uint64 ## A final descriptor position cannot substitute a source/fact/account ordinal.
  SelectedAccountWriteLimits* = object ## Traversal, descriptor allocation, predicate work and copied payload bytes remain independent.
    accounts*, facts*, writes*, checks*: ElementLimit
    valueBytes*: ByteLimit
  SelectedAccountWriteInfo* = object ## Actual selected subset counts never imply complete account or block coverage.
    accounts*, facts*, writes*: int
    valueBytes*, checks*: uint64
  SelectedAccountWriteError* {.pure.} = enum ## Default/refused alternatives contain only a typed reason.
    Uninitialized, None, InvalidSource, SourceMismatch, IncompleteFacts, InvalidState,
    LimitExceeded, ConflictingKey, InvalidIndex
  WriteRow = object # Private descriptors own fresh final payloads and exact logical account identities.
    service: ServiceIndex
    write: StateWrite
  WriteDraft = object # Explicit private work state has no exported aliases or shared mutable backing.
    limits: SelectedAccountWriteLimits
    rows: seq[WriteRow]
    facts, bytes, checks: uint64
  SelectedWritesData = ref object # Acyclic immutable sources retain their real snapshots/outcomes independently of caller handles.
    prior: PreparedAccumulationAccountSelection
    created: PreparedAccumulationCreationUnion
    rows: seq[WriteRow]
    info: SelectedAccountWriteInfo
  PreparedSelectedAccountWrites* = object ## Only complete checked preparation constructs selected physical descriptors.
    data: nil SelectedWritesData
  SelectedAccountWriteResult*[T] = object ## Read-only tags and guarded successful extraction prevent fabricated partial plans.
    case status: SelectedAccountWriteError
    of None:
      completed: T # No writable discriminator or inactive successful payload.
    else:
      discard      # Refusal retains its reason alone.

func error*[T](outcome: SelectedAccountWriteResult[T]): SelectedAccountWriteError =
  ## Inspect refusal without allowing retagging.
  outcome.status
func value*[T](outcome: SelectedAccountWriteResult[T]): T {.inline,
    requires: outcome.status == SelectedAccountWriteError.None.} =
  ## Extract only complete success under optimized checked contracts.
  outcome.completed
proc spend(draft: var WriteDraft): SelectedAccountWriteError =
  ## Charge each selected row, inspected fact, final lookup and physical-key comparison before access.
  if draft.checks >= uint64(draft.limits.checks): return SelectedAccountWriteError.LimitExceeded # No work after quota exhaustion.
  inc draft.checks
  SelectedAccountWriteError.None
proc captureKey(draft: var WriteDraft, service: ServiceIndex, key: StateKey,
    snapshot: StateStoreSnapshot): SelectedAccountWriteError =
  ## Copy only the final selected value or genuine absence for one trusted physical fact.
  let charged = draft.spend()
  if charged != SelectedAccountWriteError.None: return charged # Final lookup consumes independent work.
  for earlier in 0..<draft.rows.len:
    let checked = draft.spend()
    if checked != SelectedAccountWriteError.None: return checked # Bound conflict detection before comparison.
    if array[31, byte](draft.rows[earlier].write.key) == array[31, byte](key):
      return SelectedAccountWriteError.ConflictingKey # Never choose a physical-key winner across selected accounts/facts.
  if uint64(draft.rows.len) >= uint64(draft.limits.writes) or draft.rows.len >= high(
      int) div sizeof(WriteRow):
    return SelectedAccountWriteError.LimitExceeded # Descriptor/native storage bounds precede payload allocation.
  let final = snapshot.lookup(key)
  var write = StateWrite(key: key, kind: StateWriteKind.Delete)
  if final.error == StateStoreError.None:
    let count = uint64(final.value.byteLength)
    if count > uint64(draft.limits.valueBytes)-draft.bytes:
      return SelectedAccountWriteError.LimitExceeded # Prove aggregate addition before copying any final bytes.
    draft.bytes += count
    write = StateWrite(key: key, kind: StateWriteKind.Put, value: final.value.bytes)
  elif final.error != StateStoreError.MissingKey:
    return SelectedAccountWriteError.InvalidState # Invalid/default snapshots cannot authorize deletions.
  draft.rows.add(WriteRow(service: service, write: write))
  SelectedAccountWriteError.None
proc captureFacts(draft: var WriteDraft, service: ServiceIndex, context: AccumulationEffectContext,
    snapshot: StateStoreSnapshot, requireMetadata: bool): SelectedAccountWriteError =
  ## Filter enabled complete physical facts by this selected logical account, preserving final source ownership.
  let count = context.effectAccountWriteFactCount
  if count.error != AccumulationEffectError.None:
    return SelectedAccountWriteError.IncompleteFacts # Disabled capture is not a proof of no changed keys.
  if uint64(count.value) > uint64(draft.limits.facts)-draft.facts or uint64(count.value) > uint64(
      high(int))-draft.facts:
    return SelectedAccountWriteError.LimitExceeded # Bound every visited fact, including filtered keys and repeated source inspections.
  draft.facts += uint64(count.value)
  let metadataKey = chapterServiceKey(StateChapter(255), service)
  var metadata = false
  for index in 0..<count.value:
    let charged = draft.spend()
    if charged != SelectedAccountWriteError.None: return charged # Charge before reading/comparing the next fact.
    let fact = context.effectAccountWriteFactAt(AccumulationAccountWriteFactIndex(uint64(index))).value
    if uint32(fact.service) != uint32(service): continue # Another account's keys cannot enter this selected namespace.
    if array[31, byte](fact.key) == array[31, byte](
        metadataKey): metadata = true # Birth/deletion requires its exact real metadata fact.
    let copied = draft.captureKey(service, fact.key, snapshot)
    if copied != SelectedAccountWriteError.None: return copied # No partial descriptor plan escapes failure.
  if requireMetadata and not metadata:
    return SelectedAccountWriteError.IncompleteFacts # A birth/deletion cannot be certified solely by other account keys.
  SelectedAccountWriteError.None
proc prepareSelectedAccountWrites*(prior: PreparedAccumulationAccountSelection,
    created: PreparedAccumulationCreationUnion, limits: SelectedAccountWriteLimits): SelectedAccountWriteResult[
        PreparedSelectedAccountWrites] =
  ## Join exact-source M/n proof owners and capture bounded final physical descriptors without hashing or publication.
  template fail(reason: SelectedAccountWriteError) =
    return SelectedAccountWriteResult[PreparedSelectedAccountWrites](status: reason)
  let previous = prior.accountSelectionInfo
  let added = created.creationUnionInfo
  if previous.error != AccumulationAccountSelectionError.None or added.error !=
      AccumulationCreationError.None:
    fail(SelectedAccountWriteError.InvalidSource) # A default projection is not an initialized empty source.
  if not sameAccumulationAnnulment(prior.accountSelectionSource.value,
      created.creationUnionSource.value):
    fail(SelectedAccountWriteError.SourceMismatch) # Equal-content independently checked sources are not interchangeable certificates.
  if uint64(previous.value.accounts) > uint64(limits.accounts) or uint64(added.value.accounts) >
      uint64(limits.accounts)-uint64(previous.value.accounts) or added.value.accounts > high(
      int)-previous.value.accounts:
    fail(SelectedAccountWriteError.LimitExceeded) # Prove total traversal/native count addition before visiting rows.
  var draft = WriteDraft(limits: limits, rows: @[], facts: 0, bytes: 0, checks: 0)
  for index in 0..<previous.value.accounts:
    let charged = draft.spend()
    if charged != SelectedAccountWriteError.None: fail(
        charged) # Bound prior subset traversal independently of physical facts.
    let ordinal = AccumulationAccountSelectionIndex(uint64(index))
    let entry = prior.selectedAccountAt(ordinal).value
    case entry.origin
    of AccumulationAccountOrigin.Prior:
      discard # Prior identity contributes no physical writes, including annulled/missing supervisor outcomes.
    of AccumulationAccountOrigin.Skipped:
      let snapshot = prior.selectedAccountSnapshotAt(ordinal).value
      let key = chapterServiceKey(StateChapter(255), entry.service)
      if not entry.present: fail(SelectedAccountWriteError.InvalidSource) # A genuine unavailable-code credit cannot delete its account.
      let copied = draft.captureKey(entry.service, key, snapshot)
      if copied != SelectedAccountWriteError.None: fail(
          copied) # Code-unavailable completion changes only its initial credited metadata.
    of AccumulationAccountOrigin.Invoker, AccumulationAccountOrigin.Supervisor:
      let original = prior.selectedAccountOutcomeAt(ordinal)
      if original.error != AccumulationAccountSelectionError.None: fail(
          SelectedAccountWriteError.InvalidSource) # No substitute raw canceled execution.
      let copied = draft.captureFacts(entry.service, original.value.outcomeContext.value,
        prior.selectedAccountSnapshotAt(ordinal).value, not entry.present)
      if copied != SelectedAccountWriteError.None: fail(
          copied) # Selected final snapshot and physical facts belong to the same context.
  for index in 0..<added.value.accounts:
    let charged = draft.spend()
    if charged != SelectedAccountWriteError.None: fail(
        charged) # New accounts consume the same independent row work ceiling.
    let ordinal = AccumulationCreationIndex(uint64(index))
    let entry = created.createdAccountAt(ordinal).value
    let original = created.createdAccountOutcomeAt(ordinal).value
    let copied = draft.captureFacts(entry.service, original.outcomeContext.value,
      created.createdAccountSnapshotAt(ordinal).value, true)
    if copied != SelectedAccountWriteError.None: fail(
        copied) # Birth metadata and any later keys come only from that selected creator.
  let info = SelectedAccountWriteInfo(accounts: previous.value.accounts+added.value.accounts,
    facts: int(draft.facts), writes: draft.rows.len, valueBytes: draft.bytes, checks: draft.checks)
  SelectedAccountWriteResult[PreparedSelectedAccountWrites](status: SelectedAccountWriteError.None,
    completed: PreparedSelectedAccountWrites(data: SelectedWritesData(prior: prior,
      created: created,
      rows: draft.rows, info: info)))

proc selectedWritesInfo*(plan: PreparedSelectedAccountWrites): SelectedAccountWriteResult[
    SelectedAccountWriteInfo] =
  ## Copy actual bounded subset accounting without exposing descriptors.
  let data = plan.data
  if data == nil: return SelectedAccountWriteResult[SelectedAccountWriteInfo](
      status: SelectedAccountWriteError.Uninitialized) # No fabricated empty plan.
  SelectedAccountWriteResult[SelectedAccountWriteInfo](status: SelectedAccountWriteError.None,
      completed: data.info)
proc selectedWritesPriorSource*(plan: PreparedSelectedAccountWrites): SelectedAccountWriteResult[
    PreparedAccumulationAccountSelection] =
  ## Retain the exact prior-account selection certificate, including any certified skipped credits.
  let data = plan.data
  if data == nil: return SelectedAccountWriteResult[PreparedAccumulationAccountSelection](
      status: SelectedAccountWriteError.Uninitialized) # No substitute M source.
  SelectedAccountWriteResult[PreparedAccumulationAccountSelection](
      status: SelectedAccountWriteError.None, completed: data.prior)
proc selectedWritesNewSource*(plan: PreparedSelectedAccountWrites): SelectedAccountWriteResult[
    PreparedAccumulationCreationUnion] =
  ## Retain the exact new-account union and its collision/cancellation proof.
  let data = plan.data
  if data == nil: return SelectedAccountWriteResult[PreparedAccumulationCreationUnion](
      status: SelectedAccountWriteError.Uninitialized) # No substitute n source.
  SelectedAccountWriteResult[PreparedAccumulationCreationUnion](
      status: SelectedAccountWriteError.None, completed: data.created)
proc selectedWriteAt*(plan: PreparedSelectedAccountWrites,
    index: AccumulationSelectedWriteIndex): SelectedAccountWriteResult[StateWrite] =
  ## Return a fresh final descriptor buffer; callers cannot mutate retained physical values.
  let data = plan.data
  if data == nil: return SelectedAccountWriteResult[StateWrite](
      status: SelectedAccountWriteError.Uninitialized) # No default write payload.
  if uint64(index) >= uint64(data.rows.len): return SelectedAccountWriteResult[StateWrite](
      status: SelectedAccountWriteError.InvalidIndex) # Upper bits refuse before narrowing.
  let source = data.rows[int(uint64(index))].write
  var write = StateWrite(key: source.key, kind: source.kind, value: newSeq[byte](source.value.len))
  for offset in 0..<write.value.len: write.value[offset] = source.value[
      offset] # Immutable factory extents prove both copy bounds.
  SelectedAccountWriteResult[StateWrite](status: SelectedAccountWriteError.None, completed: write)
