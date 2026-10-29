# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"arc": "pvm_current_state_publication_arc_release"}

## Exact-parent publication adopts prepared complete snapshots without rehashing, replay or losing inherited policy/history.

import std/[assertions, envvars, syncio]
import ../../../src/state/accumulation/current/[publication as accumulation_current_publication,
    consensus as accumulation_current_consensus]
import ../../../src/state/accumulation/consensus as accumulation_consensus
import ../../../src/state/accumulation/current/authorization as accumulation_current_authorization
import ../../../src/state/accumulation/authorization as accumulation_authorization
import ../../../src/state/accumulation/current/preimages as accumulation_current_preimages
import ../../../src/state/accumulation/preimages as accumulation_preimages
import ../../../src/state/accumulation/current/activity as accumulation_current_activity
import ../../../src/state/accumulation/activity as accumulation_activity
import ../../../src/state/accumulation/current/[validators as accumulation_current_validators,
    recent as accumulation_current_recent, ready as accumulation_current_ready,
    finalization as accumulation_current_finalization, accounts as accumulation_current_accounts,
    statistics as accumulation_current_statistics, driver as accumulation_current_driver,
    sequence as accumulation_current_sequence, round as accumulation_current_round]
import "../../../src/state/accumulation/block/guests" as accumulation_block_guests
import ../../../src/state/accumulation/[round as accumulation_round, queue as accumulation_queue]
import ../../../src/state/report/admission as report_admission
import "../../../src/state/block/transition" as block_transition
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/core/service_activity as core_service_activity
import ../../../src/state/[preimages, authorization, store]
import ../../../src/codec/[bounded, composite, report_owned]
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../support/[accumulation_current_activity_context, report_context, arc_evidence]

# Prepare genuine candidates first; publication must remain successful even while every Blake2b call would refuse.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

type
  PublicationFixture = object ## Test-only complete original entries distinguish root equality from genuine retained-version identity.
    source: PreparedCurrentAccumulationConsensus
    parent: StateStoreSnapshot
    entries: seq[StateEntry]

proc fixture(base: OwnedReport, uses = 0, available = false, blobs = false, provided = false,
    disputed = false, rotated = false, ticket = false, writes = 1000'u64): PublicationFixture =
  ## Only genuine signed block, guest, stopped-history and composition constructors create publication authority.
  let authored = currentActivityFixture(base, guarantees = uses, available = available,
    blobs = blobs,
    provided = provided, withDispute = disputed, withTicket = ticket, shiftPending = rotated,
    slot = (if rotated: 12'u32 else: 2'u32), storeWrites = writes)
  let activity = prepareCurrentAccumulationActivity(authored.source, AccumulationActivityConfig(
    componentBytes: ByteLimit(1024), preimages: PreimageLimits(items: ElementLimit(3),
      perBlob: ByteLimit(3), totalBlobBytes: ByteLimit(4)), incoming: ElementLimit(2),
    available: ElementLimit(1), digests: ElementLimit(2), assurances: ElementLimit(5),
    provisions: ElementLimit(2), accumulation: ElementLimit(2), services: ElementLimit(2),
    activityBytes: ByteLimit(4096))).value
  let lookup = prepareCurrentAccumulationPreimages(activity, AccumulationPreimageLimits(
      items: ElementLimit(3),
    bytes: ByteLimit(4))).value
  let pools = prepareCurrentAccumulationAuthorization(lookup, AccumulationAuthorizationLimits(
      guarantees: ElementLimit(2),
    inputHashes: ElementLimit(160), inputBytes: ByteLimit(5120), outputHashes: ElementLimit(16),
    outputBytes: ByteLimit(514))).value
  let composed = prepareCurrentAccumulationConsensus(pools, AccumulationConsensusLimits(
    chapterBytes: ByteLimit(10000), totalBytes: ByteLimit(50000))).value
  PublicationFixture(source: composed, parent: activity.currentActivityPreimages.value.preimagePrior.value,
    entries: authored.entries)

proc admission(source: PreparedCurrentAccumulationConsensus): AdmittedReports =
  ## Retain the original authentic report/block source for an earlier-prefix negative witness.
  source.currentConsensusSource.value.currentAuthorizationSource.value.currentPreimagesSource.value.currentActivitySource.value.currentValidatorsSource.value.currentRecentSource.value.currentReadySource.value.currentFinalizationAccounts.value.currentAccountsSource.value.currentStatisticsSource.value.completedSequenceSource.value.currentSequenceInitial.value.currentRoundGuests.value.guestRound.value.roundBlockQueue.value.accumulationAdmission.value

proc witness(base: OwnedReport, uses = 0, available = false, blobs = false, provided = false,
    disputed = false, rotated = false, ticket = false) =
  ## Prepared snapshot identity proves the entire candidate is adopted, beyond equality of selected roots/entries.
  let context = fixture(base, uses, available, blobs, provided, disputed, rotated, ticket)
  let candidate = context.source.currentConsensusState.value
  var canonical = forkStateStore(context.parent).value
  let alias = canonical # This independent value handle must continue retaining the historical parent.
  let history = context.parent.lookup(chapterKey(StateChapter(11))).value
  assert sameStateSnapshot(context.parent, admission(
      context.source).reportBlockStage.value.value.admitted.admittedState)
  failHash(1)
  let published = publishCurrentAccumulationState(canonical, context.source)
  assert published.error == CurrentAccumulationPublicationError.None
  assert sameStateSnapshot(canonical.snapshot.value, candidate)
  assert sameStateSnapshot(published.value, candidate)
  assert sameStateSnapshot(alias.snapshot.value, context.parent)
  assert history.bytes == @[1'u8, 0, 0, 0], "historical owner-bound views survive publication"
  assert canonical.snapshot.value.lookup(chapterKey(StateChapter(11))).value.bytes ==
    (if rotated: @[12'u8, 0, 0, 0] else: @[2'u8, 0, 0, 0])
  let replay = publishCurrentAccumulationState(canonical, context.source)
  assert replay.error == CurrentAccumulationPublicationError.StaleState
  assert sameStateSnapshot(canonical.snapshot.value, candidate)
  var branch = forkStateStore(context.parent).value
  assert publishCurrentAccumulationState(branch, context.source).error ==
      CurrentAccumulationPublicationError.None
  assert sameStateSnapshot(branch.snapshot.value, candidate), "the same exact parent permits an independent branch publication"
  assert sameStateSnapshot(alias.snapshot.value, context.parent), "only the selected handle changes"
  assert hashCalls() == 0, "adoption/replay never rehash or re-execute the prepared transition"
  failHash(0)

proc stale(target: var StateStore, source: PreparedCurrentAccumulationConsensus) =
  ## Every wrong-version refusal preserves the target's exact existing owner while hashing is unavailable.
  let before = target.snapshot.value
  failHash(1)
  assert publishCurrentAccumulationState(target, source).error ==
      CurrentAccumulationPublicationError.StaleState
  assert sameStateSnapshot(target.snapshot.value, before)
  assert hashCalls() == 0
  failHash(0)

proc refusals(context: PublicationFixture) =
  ## Root equality cannot authorize publication, even after a real write restores the complete original bytes.
  let parent = context.parent
  var rebuilt = newStateStore(context.entries, report_context.limits()).value
  assert array[32, byte](rebuilt.snapshot.value.commitment.root) == array[32, byte](
      parent.commitment.root)
  assert not sameStateSnapshot(rebuilt.snapshot.value, parent)
  stale(rebuilt, context.source)
  var staged = forkStateStore(admission(context.source).reportBlockStage.value.value.snapshot).value
  stale(staged, context.source) # Authenticated consensus prefixes are still the wrong publication version.
  var earlier = forkStateStore(context.source.currentConsensusSource.value.currentAuthorizationState.value).value
  stale(earlier, context.source) # Accumulation-only candidates cannot impersonate the admitted parent.
  var changed = forkStateStore(parent).value
  let key = chapterKey(StateChapter(250))
  let original = parent.lookup(key).value.bytes
  assert changed.apply([StateWrite(key: key, kind: StateWriteKind.Put, value: @[0'u8])]).error ==
      StateStoreError.None
  assert array[32, byte](changed.snapshot.value.commitment.root) != array[32, byte](
      parent.commitment.root)
  stale(changed, context.source)
  assert changed.apply([StateWrite(key: key, kind: StateWriteKind.Put, value: original)]).error ==
      StateStoreError.None
  assert array[32, byte](changed.snapshot.value.commitment.root) == array[32, byte](
      parent.commitment.root)
  assert not sameStateSnapshot(changed.snapshot.value, parent)
  stale(changed, context.source)
  var fresh = forkStateStore(parent).value
  failHash(1)
  let invalid = publishCurrentAccumulationState(fresh, default(PreparedCurrentAccumulationConsensus))
  assert invalid.error == CurrentAccumulationPublicationError.InvalidSource
  assert sameStateSnapshot(fresh.snapshot.value, parent)
  var empty = default(StateStore)
  let uninitialized = publishCurrentAccumulationState(empty, context.source)
  assert uninitialized.error == CurrentAccumulationPublicationError.StateFailure
  assert uninitialized.stateError == StateStoreError.Uninitialized
  assert empty.snapshot.error == StateStoreError.Uninitialized
  assert hashCalls() == 0
  failHash(0)
  assert publishCurrentAccumulationState(fresh, context.source).error ==
      CurrentAccumulationPublicationError.None, "a refused invalid source did not consume the real parent handle"

proc inherited(base: OwnedReport) =
  ## The adopted map's original seven-write policy remains active for later operations, without reset or override.
  let context = fixture(base, uses = 2, blobs = true, writes = 7)
  var canonical = forkStateStore(context.parent).value
  failHash(1)
  assert publishCurrentAccumulationState(canonical, context.source).error ==
      CurrentAccumulationPublicationError.None
  assert hashCalls() == 0
  failHash(0)
  let before = canonical.snapshot.value
  var writes: seq[StateWrite] = @[]
  for chapter in 1'u8..8'u8:
    let key = chapterKey(StateChapter(chapter))
    writes.add(StateWrite(key: key, kind: StateWriteKind.Put,
      value: before.lookup(key).value.bytes)) # Fixed distinct keys avoid duplicate- or shape-based false refusals.
  failHash(1)
  assert canonical.apply(writes).error == StateStoreError.LimitExceeded
  assert sameStateSnapshot(canonical.snapshot.value, before)
  assert hashCalls() == 0
  failHash(0)
  assert canonical.apply(writes.toOpenArray(0, 6)).error == StateStoreError.None, "exact seven-write boundary still passes"
  assert array[32, byte](canonical.snapshot.value.commitment.root) == array[32, byte](
      before.commitment.root)

proc cycle(context: PublicationFixture) =
  ## Scoped success/replay/uninitialized-target/invalid-source results release every new handle and result owner.
  failHash(1)
  var target = forkStateStore(context.parent).value
  let published = publishCurrentAccumulationState(target, context.source)
  assert published.error == CurrentAccumulationPublicationError.None
  assert sameStateSnapshot(published.value, context.source.currentConsensusState.value)
  assert publishCurrentAccumulationState(target, context.source).error ==
      CurrentAccumulationPublicationError.StaleState
  var empty = default(StateStore)
  assert publishCurrentAccumulationState(empty, context.source).stateError ==
      StateStoreError.Uninitialized
  var other = forkStateStore(context.parent).value
  let invalid = publishCurrentAccumulationState(other, default(PreparedCurrentAccumulationConsensus))
  assert invalid.error == CurrentAccumulationPublicationError.InvalidSource
  assert sameStateSnapshot(other.snapshot.value, context.parent)
  assert hashCalls() == 0
  failHash(0)

proc main() {.raises.} =
  ## The native launcher supplies pinned report bytes; actual preparation establishes every tested source capability.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<wire.len: wire[index] = byte(raw[index])
  let base = decodeOwnedReport(wire, 2).value
  witness(base)
  witness(base, uses = 2)
  witness(base, uses = 2, available = true, blobs = true, provided = true)
  witness(base, disputed = true)
  witness(base, rotated = true)
  witness(base, ticket = true)
  let context = fixture(base, uses = 2, blobs = true, provided = true)
  refusals(context)
  inherited(base)
  var detached = default(StateStoreSnapshot)
  block:
    let local = fixture(base, uses = 2, available = true, blobs = true, provided = true)
    var canonical = forkStateStore(local.parent).value
    failHash(1)
    detached = publishCurrentAccumulationState(canonical, local.source).value
    assert sameStateSnapshot(detached, local.source.currentConsensusState.value)
    failHash(0) # All preparation owners and the target handle are released at scope exit.
  assert detached.lookup(chapterKey(StateChapter(11))).value.bytes == @[2'u8, 0, 0, 0]
  cycle(context)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(context) # The original authority stays fixed; newly published handle/result copies are scoped.
  let after = getOccupiedMem()
  assert before == after, "guarded publication ARC release"
  recordArcRelease("pvm_current_state_publication", 1000, before, after)
  echo "PVM current state publication passed"
  echo "ARC_RELEASE cycles=1000 unchanged"

try:
  main() # Fixture I/O errors are strict native failures.
except:
  quit(2)
