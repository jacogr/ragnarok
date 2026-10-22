# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent sixteen-chapter fixtures and service evidence roundtrip through exact planned projections.
import std/[assertions, envvars, syncio]
import ../../support/proof_global_helpers
import ../../../src/state/[proof_global, proof_plan, proof_view, proof_service, planned_proof, trie_proof]
import ../../../src/codec/[bounded, assurances, state_layout, state_trie, state_accounts,
    state_safrole, state_consensus, state_composition]
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset the maintained backend observer to prove projection never rehashes already verified facts.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Measure every attempted hash after source authentication.
proc main() {.raises.} =
  ## Exercise mixed scope under one independently computed root without complete-state conversion.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  var entries: seq[StateEntry] = @[]
  var chapters: seq[StateChapterId] = @[]
  for i in 1..16:
    # Literal independent fixture bytes retain the exact existing pinned chapter schemas.
    entries.add(StateEntry(key: chapterKey(StateChapter(i)), value: fixture[i-1]))
    chapters.add(StateChapterId(i))
  let service = ServiceIndex(7)
  let account = serviceMetadataEntry(service, default(ServiceMetadata), ByteLimit(105)).value
  entries.add(account)
  let globals = planProofChapters(chapters, ElementLimit(16)).value
  let services = planProofAccount(service, ElementLimit(1)).value.toStateProofPlan
  let mixed = mergeStateProofPlans(globals, services, ElementLimit(17)).value
  let absentKey = chapterKey(StateChapter(99))
  var keys: seq[StateKey] = @[]
  for key in mixed: keys.add(key) # The source additionally authenticates one explicitly absent identity.
  keys.add(absentKey)
  let source = globalView(entries, keys)
  let trusted = source.root
  fail(1)
  let exact = projectPlannedProofs(source, mixed, viewLimits).value
  assert matchesStateProofPlan(exact, mixed).value
  assert array[32, byte](exact.root) == array[32, byte](trusted)
  assert exact.readProofAccount(service).error == ServiceProofError.None
  let profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
    previous: ValidatorCount(6), epochSlots: EpochSlots(2))
  let policy = StateChapterPolicy(items: ElementLimit(1000), maxBytes: ByteLimit(65536))
  for chapter in chapters:
    assert exact.readProofChapter(chapter, profile, policy).error ==
        GlobalProofError.None # Every exact fixture chapter remains typed-decodable.
  let absentPlan = captureStateProofPlan([absentKey], ElementLimit(1)).value
  let absent = projectPlannedProofs(source, absentPlan, viewLimits).value
  assert not absent.lookup(absentKey).value.present
  assert projectPlannedProofs(exact, absentPlan, viewLimits).error == ProofViewError.MissingWitness
  assert projectPlannedProofs(source, default(StateProofPlan), viewLimits).error ==
      ProofViewError.Uninitialized
  assert projectPlannedProofs(default(ProofView), mixed, viewLimits).error ==
      ProofViewError.Uninitialized
  assert projectPlannedProofs(source, mixed, ProofViewLimits(items: ElementLimit(16),
      valueBytes: ByteLimit(262144))).error == ProofViewError.LimitExceeded
  assert projectPlannedProofs(source, mixed, ProofViewLimits(items: ElementLimit(17),
      valueBytes: ByteLimit(0))).error == ProofViewError.LimitExceeded
  let emptyPlan = captureStateProofPlan([], ElementLimit(0)).value
  assert projectPlannedProofs(source, emptyPlan, viewLimits).value.len == 0
  assert calls() == 0
  fail(0)
  let wire = encodePlannedProofs(exact, mixed, viewLimits, proofLimits, ByteLimit(262144)).value
  let received = decodePlannedProofs(wire, mixed, trusted, viewLimits, proofLimits, batchLimits,
      ByteLimit(262144)).value
  for chapter in chapters:
    assert received.readProofChapter(chapter, profile, policy).error ==
        GlobalProofError.None # Transport grants only the same exact chapter facts.
  assert received.readProofAccount(service).error == ServiceProofError.None
  assert received.lookup(absentKey).error == ProofViewError.MissingWitness
  assert encodePlannedProofs(source, mixed, viewLimits, proofLimits, ByteLimit(262144)).error ==
      ProofViewError.NonCanonical
  echo "state-global-mixed-reads: ok"
try:
  main()
except:
  quit(2) # Independent fixture setup is mandatory for this mixed protocol witness.
