# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "accumulation_state_arc_release"}

## Atomic state application checks exact-parent authority, private failure rollback and one-pass composition.

import std/assertions
import std/envvars
import std/syncio
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/state/accumulation_state as state_accumulation_state
import ../../../src/state/accumulation_finalization as state_accumulation_finalization
import ../../../src/state/accumulation_completion as state_accumulation_completion
import ../../../src/state/accumulation_consensus as state_accumulation_consensus
import ../../../src/state/accumulation_authorization as state_accumulation_authorization
import ../../../src/state/accumulation_preimages as state_accumulation_preimages
import ../../../src/state/accumulation_activity as state_accumulation_activity
import ../../../src/state/accumulation_validators as state_accumulation_validators
import ../../../src/state/accumulation_times as state_accumulation_times
import ../../../src/state/accumulation_statistics as state_accumulation_statistics
import ../../../src/state/accumulation_history as state_accumulation_history
import ../../../src/state/accumulation_ready as state_accumulation_ready
import ../../../src/state/accumulation_recent as state_accumulation_recent
import ../../../src/state/store as state_store
import ../../support/state_accumulation_activity_context
import ../../support/state_accumulation_completion_context
import ../../support/state_report_context
import ../../support/testing_arc_evidence

# Failure injection begins only after the real signed execution successor and expected map exist.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

type
  StateFixture = object ## Test-only source and complete oracle come from independently spelled existing state phases.
    source: PreparedFinalAccumulation
    expected: StateStoreSnapshot
    entries: seq[StateEntry]

proc fixture(base: OwnedReport, uses = 0, available = false, blobs = false, provided = false,
    disputed = false, rotated = false, ticket = false, writes = 1000'u64): StateFixture =
  ## The helper genuinely signs and executes a block; no raw state owner can impersonate its authority.
  let authored = activityFixture(base, guarantees = uses, available = available, blobs = blobs,
    provided = provided, withDispute = disputed, withTicket = ticket, shiftPending = rotated,
    slot = (if rotated: 12'u32 else: 2'u32), storeWrites = writes)
  let source = authored.source.accumulationValidatorsSource.value.accumulationTimesStatistics.value.statisticsSource.value
  var expected = default(StateStoreSnapshot)
  if writes >= 7:
    # Earlier phases were constructed independently by the existing fixture; finish the explicit oracle chain.
    let limits = completionLimits().composition
    let activity = prepareAccumulationActivity(authored.source, limits.activity).value
    let preimages = prepareAccumulationPreimages(activity, limits.preimages).value
    let authorization = prepareAccumulationAuthorization(preimages, limits.authorization).value
    expected = prepareAccumulationConsensus(authorization,
        limits.consensus).value.accumulationConsensusState.value
  StateFixture(source: source, expected: expected, entries: authored.entries)

proc witness(context: StateFixture, slot = 2'u8) =
  ## Validate the complete expected map, exact adopted identity, historical aliases and one composition pass.
  let sourceBefore = context.source.finalAccumulationState.value
  let parent = context.source.finalAccumulationParent.value
  let policy = completionLimits().composition
  failHash(0)
  discard prepareAccumulationComposition(context.source, policy).value
  let expectedHashes = hashCalls()
  assert expectedHashes > 0, "composition has observable state work"
  var target = forkStateStore(parent).value
  let alias = target
  let historical = parent.lookup(chapterKey(StateChapter(11))).value
  failHash(0)
  let outcome = applyAccumulationState(target, context.source, policy)
  assert outcome.error == AccumulationStateError.None, $outcome.error
  assert hashCalls() == expectedHashes, "application composes once without executing or refinalizing guests"
  let candidate = outcome.value
  assert sameStateSnapshot(target.snapshot.value, candidate)
  assert array[32, byte](candidate.commitment.root) == array[32, byte](
      context.expected.commitment.root)
  assert candidate.commitment.entries == context.expected.commitment.entries
  for entry in context.entries:
    # Check every original key against the independently constructed complete successor, including opaque entries.
    let expected = context.expected.lookup(entry.key)
    let actual = candidate.lookup(entry.key)
    assert actual.error == expected.error
    if expected.error == StateStoreError.None:
      assert actual.value.bytes == expected.value.bytes
  assert candidate.lookup(chapterKey(StateChapter(11))).value.bytes == @[slot, 0, 0, 0]
  assert historical.bytes == @[1'u8, 0, 0, 0]
  assert sameStateSnapshot(alias.snapshot.value, parent)
  assert sameStateSnapshot(context.source.finalAccumulationState.value, sourceBefore)
  failHash(1)
  let replay = applyAccumulationState(target, context.source, default(AccumulationCompositionLimits))
  assert replay.error == AccumulationStateError.StaleState and hashCalls() == 0
  assert sameStateSnapshot(target.snapshot.value, candidate)
  failHash(0)
  var branch = alias
  assert applyAccumulationState(branch, context.source, policy).error == AccumulationStateError.None
  assert sameStateSnapshot(alias.snapshot.value, parent), "independent exact-parent handles remain valid publication branches"

proc stale(target: var StateStore, source: PreparedFinalAccumulation) =
  ## Wrong-parent identity wins over deliberately invalid composition policies before any provider work.
  let before = target.snapshot.value
  failHash(1)
  let outcome = applyAccumulationState(target, source, default(AccumulationCompositionLimits))
  assert outcome.error == AccumulationStateError.StaleState
  assert sameStateSnapshot(target.snapshot.value, before) and hashCalls() == 0
  failHash(0)

proc preflight(context: StateFixture) =
  ## Equal bytes/roots, execution-stage snapshots and restored versions do not establish original-parent identity.
  let parent = context.source.finalAccumulationParent.value
  var rebuilt = newStateStore(context.entries, state_report_context.limits()).value
  assert array[32, byte](rebuilt.snapshot.value.commitment.root) == array[32, byte](
      parent.commitment.root)
  assert not sameStateSnapshot(rebuilt.snapshot.value, parent)
  stale(rebuilt, context.source)
  var execution = forkStateStore(context.source.finalAccumulationState.value).value
  stale(execution, context.source)
  var restored = forkStateStore(parent).value
  let key = chapterKey(StateChapter(250))
  let original = parent.lookup(key).value.bytes
  assert restored.apply([StateWrite(key: key, kind: StateWriteKind.Put, value: @[0'u8])]).error ==
      StateStoreError.None
  stale(restored, context.source)
  assert restored.apply([StateWrite(key: key, kind: StateWriteKind.Put, value: original)]).error ==
      StateStoreError.None
  assert array[32, byte](restored.snapshot.value.commitment.root) == array[32, byte](
      parent.commitment.root)
  stale(restored, context.source)
  var valid = forkStateStore(parent).value
  var missing = default(StateStore)
  failHash(1)
  assert applyAccumulationState(valid, default(PreparedFinalAccumulation), default(
      AccumulationCompositionLimits)).error == AccumulationStateError.InvalidSource
  assert applyAccumulationState(missing, default(PreparedFinalAccumulation), default(
      AccumulationCompositionLimits)).error == AccumulationStateError.InvalidSource
  let absent = applyAccumulationState(missing, context.source, default(AccumulationCompositionLimits))
  assert absent.error == AccumulationStateError.StateFailure
  assert absent.stateError == StateStoreError.Uninitialized
  assert missing.snapshot.error == StateStoreError.Uninitialized
  assert sameStateSnapshot(valid.snapshot.value, parent) and hashCalls() == 0
  let uninitialized = default(AccumulationStateResult)
  assert uninitialized.error == AccumulationStateError.Uninitialized
  failHash(0)

proc quotas(context: StateFixture) =
  ## Every failed composition phase preserves the target and its original nested reason.
  let parent = context.source.finalAccumulationParent.value
  let sourceBefore = context.source.finalAccumulationState.value
  let reasons = [AccumulationCompletionError.HistoryFailure,
    AccumulationCompletionError.ReadyFailure,
    AccumulationCompletionError.RecentFailure, AccumulationCompletionError.TimesFailure,
    AccumulationCompletionError.ValidatorsFailure, AccumulationCompletionError.ActivityFailure,
    AccumulationCompletionError.PreimagesFailure, AccumulationCompletionError.AuthorizationFailure,
    AccumulationCompletionError.ConsensusFailure]
  for index, reason in reasons:
    var short = completionLimits().composition
    case index
    of 0: short.history.reports = ElementLimit(0) # Bound the genuinely processed report history.
    of 1: short.ready.items = ElementLimit(0) # Bound retained ready work.
    of 2: short.recent.headerBytes = ByteLimit(0) # Bound the original sealed header.
    of 3: short.times.statistics.rounds = ElementLimit(0) # Bound certified execution history traversal.
    of 4: short.validators.chapterBytes = ByteLimit(0) # Bound retained parent activity/rosters.
    of 5: short.activity.componentBytes = ByteLimit(0) # Bound original signed components.
    of 6: short.preimages.items = ElementLimit(0) # Bound authenticated lookup/preimage work.
    of 7: short.authorization.inputBytes = ByteLimit(0) # Bound parent pools and posterior queues.
    else: short.consensus.chapterBytes = ByteLimit(0) # Refuse the final overlay after earlier private work.
    var target = forkStateStore(parent).value
    let outcome = applyAccumulationState(target, context.source, short)
    assert outcome.error == AccumulationStateError.CompositionFailure
    assert outcome.compositionFailure.error == reason, $outcome.compositionFailure.error
    assert sameStateSnapshot(target.snapshot.value, parent)
    assert sameStateSnapshot(context.source.finalAccumulationState.value, sourceBefore)

proc backends(context: StateFixture) =
  ## Early and last-hash refusal leave the exact caller owner intact, and the same handle/source can retry.
  let parent = context.source.finalAccumulationParent.value
  let policy = completionLimits().composition
  var target = forkStateStore(parent).value
  failHash(1)
  let early = applyAccumulationState(target, context.source, policy)
  assert early.error == AccumulationStateError.CompositionFailure
  assert sameStateSnapshot(target.snapshot.value, parent)
  failHash(0)
  discard prepareAccumulationComposition(context.source, policy).value
  let cost = hashCalls()
  assert cost > 0
  failAfter(cost-1)
  let late = applyAccumulationState(target, context.source, policy)
  failHash(0)
  assert late.error == AccumulationStateError.CompositionFailure
  assert late.compositionFailure.error == AccumulationCompletionError.ConsensusFailure
  assert late.compositionFailure.consensusFailure.stateError == StateStoreError.BackendFailure
  assert sameStateSnapshot(target.snapshot.value, parent)
  assert applyAccumulationState(target, context.source, policy).error == AccumulationStateError.None
  assert array[32, byte](target.snapshot.value.commitment.root) == array[32, byte](
      context.expected.commitment.root)

proc cycle(context: StateFixture) =
  ## Scoped success, stale replay and late policy failure release all intermediate graphs and published handles.
  let parent = context.source.finalAccumulationParent.value
  let policy = completionLimits().composition
  var target = forkStateStore(parent).value
  let outcome = applyAccumulationState(target, context.source, policy)
  assert outcome.error == AccumulationStateError.None
  assert applyAccumulationState(target, context.source, policy).error ==
      AccumulationStateError.StaleState
  var short = policy
  short.consensus.chapterBytes = ByteLimit(0)
  var refused = forkStateStore(parent).value
  assert applyAccumulationState(refused, context.source, short).compositionFailure.error ==
      AccumulationCompletionError.ConsensusFailure
  assert sameStateSnapshot(refused.snapshot.value, parent)

proc main() {.raises.} =
  ## Native fixture verification precedes genuine signing; no test manufactures a successful execution certificate.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  witness(fixture(base))
  witness(fixture(base, uses = 2))
  witness(fixture(base, uses = 2, available = true, blobs = true, provided = true))
  witness(fixture(base, disputed = true))
  witness(fixture(base, rotated = true), 12)
  witness(fixture(base, ticket = true))
  let context = fixture(base, uses = 2, available = true, blobs = true, provided = true)
  preflight(context)
  let foreign = fixture(base, uses = 1)
  var target = forkStateStore(foreign.source.finalAccumulationParent.value).value
  stale(target, context.source)
  quotas(context)
  backends(context)
  let capped = fixture(base, writes = 6)
  let parent = capped.source.finalAccumulationParent.value
  var limited = forkStateStore(parent).value
  let rejected = applyAccumulationState(limited, capped.source, completionLimits().composition)
  assert rejected.compositionFailure.consensusFailure.stateError == StateStoreError.LimitExceeded
  assert sameStateSnapshot(limited.snapshot.value, parent)
  var detached = default(StateStoreSnapshot)
  block:
    # Result snapshot retention survives source, fixture and mutable target destruction.
    let local = fixture(base, uses = 2, blobs = true, provided = true)
    var caller = forkStateStore(local.source.finalAccumulationParent.value).value
    detached = applyAccumulationState(caller, local.source, completionLimits().composition).value
  assert detached.lookup(chapterKey(StateChapter(11))).value.bytes == @[2'u8, 0, 0, 0]
  cycle(context)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(context) # Fresh private graphs are released after every success/refusal pair.
  let after = getOccupiedMem()
  assert before == after, "atomic accumulation state ARC release"
  recordArcRelease("state_accumulation_state", 1000, before, after)
  echo "Atomic accumulation state application passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fixture I/O errors must fail the native test.
except:
  quit(2)
