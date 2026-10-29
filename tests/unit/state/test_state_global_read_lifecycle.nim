# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Typed chapter captures, planned projections and refusal paths release every derived ARC owner.
# @@Verification={"arc": "state_global_read_lifecycle_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[proof_global_helpers, arc_evidence]
import ../../../src/state/proof/[global as proof_global, view as proof_view]
import ../../../src/state/planned/proof as planned_proof
import ../../../src/codec/[bounded, assurances]
import ../../../src/codec/state/[layout as state_layout, trie as state_trie,
    composition as state_composition, consensus as state_consensus, safrole as state_safrole,
    authorization as state_authorization, history as state_history, disputes as state_disputes,
    availability as state_availability]
import ../../../src/codec/guarantees
import ../../../src/codec/state/[privileges as state_privileges, statistics as state_statistics,
    workqueues as state_workqueues, outputs as state_outputs]
include ../../native/composition_fixture
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
