# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Typed chapter captures, planned projections and refusal paths release every derived ARC owner.
# @@Verification={"arc": "state_global_read_lifecycle_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_proof_global_helpers
import ../../support/testing_arc_evidence
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/planned_proof as state_planned_proof
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_consensus as codec_state_consensus
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_authorization as codec_state_authorization
import ../../../src/codec/state_history as codec_state_history
import ../../../src/codec/state_disputes as codec_state_disputes
import ../../../src/codec/state_availability as codec_state_availability
import ../../../src/codec/guarantees as codec_guarantees
import ../../../src/codec/state_privileges as codec_state_privileges
import ../../../src/codec/state_statistics as codec_state_statistics
import ../../../src/codec/state_workqueues as codec_state_workqueues
import ../../../src/codec/state_outputs as codec_state_outputs
include ../../native/nimony_composition_fixture
proc cycle(source: ProofView) =
  ## Every temporary plan, partial owner and typed chapter dies before the allocator is sampled.
  let profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
      previous: ValidatorCount(6), epochSlots: EpochSlots(2))
  let policy = StateChapterPolicy(items: ElementLimit(1000), maxBytes: ByteLimit(65536))
  let queues = WorkQueueConfig(cores: CoreCount(2), epochSlots: EpochSlots(2),
      perSlot: ElementLimit(1000), totalItems: ElementLimit(1000),
    perDependencies: ElementLimit(1000), totalDependencies: ElementLimit(1000),
        reportBytes: ByteLimit(65536), maxBytes: ByteLimit(65536))
  let roster = ValidatorStateConfig(cores: CoreCount(2), validators: ElementLimit(1000),
      maxBytes: ByteLimit(65536))
  var chapters: seq[StateChapterId] = @[]
  for i in 1..16: chapters.add(StateChapterId(i)) # Fixed nominal fixture slots contain no untrusted narrowing.
  let plan = planProofChapters(chapters, ElementLimit(16)).value
  let view = projectPlannedProofs(source, plan, viewLimits).value
  for chapter in chapters:
    assert view.readProofChapter(chapter, profile, policy).error ==
        GlobalProofError.None # Typed captures retain no leaked immutable owner.
  assert view.readGlobalTime.error == GlobalProofError.None
  assert view.readGlobalEntropy(policy.maxBytes).error == GlobalProofError.None
  for kind in [AuthorizationKind.Pools, AuthorizationKind.Queues]:
    assert view.readGlobalAuthorization(kind, AuthorizationConfig(cores: profile.cores,
        maxHashes: policy.items, maxBytes: policy.maxBytes)).error ==
        GlobalProofError.None # Both row schemas retire independently.
  for chapter in [ValidatorChapter.Staging, ValidatorChapter.Active, ValidatorChapter.Previous]:
    assert view.readGlobalValidators(chapter, roster).error ==
        GlobalProofError.None # All roster owners release their records.
  assert view.readGlobalHistory(HistoryConfig(cores: profile.cores, blocks: policy.items,
      perBlock: policy.items, totalPackages: policy.items, peaks: policy.items,
      maxBytes: policy.maxBytes)).error == GlobalProofError.None
  assert view.readGlobalSafrole(SafroleStateConfig(validators: roster,
      epochSlots: profile.epochSlots, maxAccumulator: policy.items,
      maxBytes: policy.maxBytes)).error == GlobalProofError.None
  assert view.readGlobalDisputes(DisputeStateConfig(perSet: policy.items, totalItems: policy.items,
      maxBytes: policy.maxBytes)).error == GlobalProofError.None
  assert view.readGlobalAvailability(AvailabilityConfig(guarantee: GuaranteeConfig(
      cores: profile.cores, validators: profile.current, maxBytes: policy.maxBytes),
      maxPresent: policy.items, maxBytes: policy.maxBytes)).error == GlobalProofError.None
  assert view.readGlobalPrivileges(PrivilegeConfig(cores: profile.cores, maxAlways: policy.items,
      maxBytes: policy.maxBytes)).error == GlobalProofError.None
  assert view.readGlobalStatistics(ActivityConfig(cores: profile.cores, current: profile.current,
      previous: profile.previous, maxServices: policy.items, maxBytes: policy.maxBytes)).error ==
      GlobalProofError.None
  assert view.readGlobalReady(queues).error == GlobalProofError.None
  assert view.readGlobalAccumulated(queues).error == GlobalProofError.None
  assert view.readGlobalOutputs(OutputLogConfig(items: policy.items,
      maxBytes: policy.maxBytes)).error == GlobalProofError.None
  assert view.readGlobalEntropy(ByteLimit(0)).error == GlobalProofError.LimitExceeded
  assert projectPlannedProofs(source, plan, ProofViewLimits()).error == ProofViewError.LimitExceeded
proc main() {.raises.} =
  ## Authenticate the independent chapter fixture once, then measure only derived owner lifetimes.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var entries: seq[StateEntry] = @[]
  var keys: seq[StateKey] = @[]
  for i in 1..16:
    # Test-only complete-map inputs establish the root; production derived views remain partial.
    let key = chapterKey(StateChapter(i))
    entries.add(StateEntry(key: key, value: fixture[i-1]))
    keys.add(key)
  let source = globalView(entries, keys)
  for i in 0..<25: cycle(source) # Warm the exact allocator graph before the live-byte observation.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(source) # All successful and refused derived captures retire inside each activation.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_global_read_lifecycle", 1000, before, after)
  echo "state-global-read-lifecycle: ok"
try:
  main()
except:
  quit(2) # Fixture transport failure is not successful ARC evidence.
