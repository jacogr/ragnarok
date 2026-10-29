# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_recent_arc_release"}

## Complete original/corrected history, exact recent tuple, endpoint coherence and immutable lifetime.

import std/[assertions, syncio]
import ../../../src/state/computed/[recent as computed_recent, state as computed_state]
import ../../../src/state/store
import ../../../src/codec/bounded
import ../../../src/codec/state/[history as state_history, layout as state_layout,
    trie as state_trie]
import ../../../src/codec/assurances
import ../../support/[pvm_computed_recent, pvm_computed_state_vectors, pvm_computed_state, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse hashes after all genuine execution/admission fixtures have been prepared.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count primitive attempts without replacing successful provider behavior.
proc expect[T](outcome: ComputedRecentResult[T], reason: ComputedRecentError) =
  ## Compare typed alternatives before any selected success extraction.
  assert outcome.error == reason, "computed recent reason"
proc literalHistory(): seq[byte] =
  ## Independently spell E2-record-count, two E(header,superPeak,state,E4slot,empty pairs), empty belt.
  result = newSeq[byte](204)
  result[0] = 2
  result[1] = 1
  result[33] = 3
  result[65] = 2
  result[97] = 18
  for index in 0..<32: result[102+index] = StateParentHash[
      index] # Latest header starts after one complete 101-byte record.
  result[134] = 9
  result[198] = 20
var fixture = recentFixture()
let source = fixture.source
assert fixture.original == literalHistory(), "independent complete original C3 wire"
let original = source.computedStateSnapshot.value
let root = array[32, byte](original.commitment.root)
let recent = checkComputedRecentAnchor(source, recentConfig()).value
let record = recent.computedRecentAnchor.value
assert array[32, byte](record.header) == StateParentHash, "exact original anchor hash"
assert uint32(record.slot) == 20, "exact original anchor slot"
assert array[32, byte](record.superPeak) == recentHash(9), "exact original accumulation super-peak"
assert array[32, byte](record.state) == root, "newest placeholder corrected from exact admitted complete map"
let history = recent.computedRecentHistory.value
assert historyInfo(history).value.blocks == 2, "no append or trim during correction"
assert array[32, byte](historyBlockAt(history, HistoryBlockIndex(0)).value.state) == recentHash(2), "earlier state root untouched"
assert array[32, byte](historyBlockAt(history, HistoryBlockIndex(1)).value.state) == root, "latest corrected history retained"
assert original.lookup(chapterKey(StateChapter(3))).value.bytes == literalHistory(), "original committed C3 unchanged"
assert sameStateSnapshot(recent.computedRecentSource.value.computedStateSnapshot.value, original), "exact original execution/admission source retained"
var changed = recent.computedRecentAnchor.value
changed.state = HistoryStateRoot(recentHash(77))
changed.slot = HistorySlot(99)
assert array[32, byte](recent.computedRecentAnchor.value.state) == root, "matched record is an isolated fixed copy"
var exact = recentConfig()
exact.maxBytes = ByteLimit(uint64(fixture.original.len))
expect(checkComputedRecentAnchor(source, exact), ComputedRecentError.None)
var short = exact
short.maxBytes = ByteLimit(uint64(fixture.original.len-1))
expect(checkComputedRecentAnchor(source, short), ComputedRecentError.LimitExceeded)
var few = exact
few.blocks = ElementLimit(1)
expect(checkComputedRecentAnchor(source, few), ComputedRecentError.LimitExceeded)
var wide = exact
wide.maxBytes = ByteLimit(high(uint64))
expect(checkComputedRecentAnchor(source, wide), ComputedRecentError.None)
var foreign = recentConfig()
foreign.cores = CoreCount(3)
expect(checkComputedRecentAnchor(source, foreign), ComputedRecentError.InvalidConfig)
expect(checkComputedRecentAnchor(default(StateBoundComputedReport), foreign),
    ComputedRecentError.InvalidSource)
expect(default(ComputedRecentResult[RecentComputedReport]), ComputedRecentError.Uninitialized)
expect(default(RecentComputedReport).computedRecentSource, ComputedRecentError.Uninitialized)
expect(default(RecentComputedReport).computedRecentHistory, ComputedRecentError.Uninitialized)
expect(default(RecentComputedReport).computedRecentAnchor, ComputedRecentError.Uninitialized)
# Each negative source still passed real original execution and exact block/state commitment admission.
for mode in 1..5:
  let invalid = recentFixture(mode)
  expect(checkComputedRecentAnchor(invalid.source, recentConfig()),
      ComputedRecentError.InvalidRecentAnchor)
let earlier = recentFixture(6)
let old = checkComputedRecentAnchor(earlier.source, recentConfig()).value.computedRecentAnchor.value
assert uint32(old.slot) == 18, "earlier complete tuple accepted"
assert array[32, byte](old.state) == recentHash(2), "earlier tuple never receives newest-state correction"
for mode in [7, 8, 11, 12]:
  let invalid = recentFixture(mode)
  expect(checkComputedRecentAnchor(invalid.source, recentConfig()),
      ComputedRecentError.InvalidHistory)
let missing = recentFixture(9)
expect(checkComputedRecentAnchor(missing.source, recentConfig()), ComputedRecentError.MissingState)
let empty = recentFixture(10)
expect(checkComputedRecentAnchor(empty.source, recentConfig()),
    ComputedRecentError.InvalidRecentAnchor)
let overwritten = recentFixture(13)
let repaired = checkComputedRecentAnchor(overwritten.source, recentConfig()).value
assert array[32, byte](repaired.computedRecentAnchor.value.state) ==
  array[32, byte](overwritten.source.computedStateSnapshot.value.commitment.root), "correct any stored latest value without changing earlier roots"
# Caller publication cannot replace either the original chapter or the completed corrected snapshot.
changeState(fixture.state)
assert not sameStateSnapshot(fixture.state.snapshot.value, original), "caller store advanced"
assert original.lookup(chapterKey(StateChapter(3))).value.bytes == literalHistory(), "original chapter remains intact after caller publication"
assert array[32, byte](recent.computedRecentAnchor.value.state) == root, "retained corrected anchor remains intact"
reset(1)
expect(checkComputedRecentAnchor(source, exact), ComputedRecentError.None)
expect(checkComputedRecentAnchor(source, short), ComputedRecentError.LimitExceeded)
expect(checkComputedRecentAnchor(missing.source, recentConfig()), ComputedRecentError.MissingState)
assert hashes() == 0, "recent correction and tuple checking perform no hashes"
reset(0)
proc detached(): RecentComputedReport =
  ## Retain exact source/state and corrected history after every temporary fixture handle retires.
  let fixture = recentFixture()
  checkComputedRecentAnchor(fixture.source, recentConfig()).value
let retained = detached()
assert uint32(retained.computedRecentAnchor.value.slot) == 20, "detached anchor lifetime"
assert historyInfo(retained.computedRecentHistory.value).value.blocks == 2, "detached history lifetime"
assert array[32, byte](retained.computedRecentAnchor.value.state) ==
  array[32, byte](retained.computedRecentSource.value.computedStateSnapshot.value.commitment.root), "detached source/state lifetime"
proc cycle(exact, short: HistoryConfig) =
  ## Release corrected C3 copies and acyclic source/history ownership on accepted and refused paths.
  let done = checkComputedRecentAnchor(source, exact).value
  assert uint32(done.computedRecentAnchor.value.slot) == 20
  discard done.computedRecentSource.value
  discard done.computedRecentHistory.value
  expect(checkComputedRecentAnchor(source, short), ComputedRecentError.LimitExceeded)
  expect(checkComputedRecentAnchor(empty.source, recentConfig()),
      ComputedRecentError.InvalidRecentAnchor)
cycle(exact, short)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(exact, short)
let after = getOccupiedMem()
assert before == after, "computed recent ARC release"
recordArcRelease("pvm_computed_recent", 1000, before, after)
echo "PVM computed recent passed"
echo "ARC_RELEASE cycles=1000 unchanged"
