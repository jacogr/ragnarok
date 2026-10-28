# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently authenticated chapter/time reads preserve missing, absent, malformed and bounded outcomes.
import std/assertions
import std/syncio
import ../../support/state_proof_global_helpers
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/proof_view as state_proof_view
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/assurances as codec_assurances
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_safrole as codec_state_safrole
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_consensus as codec_state_consensus
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset the maintained backend observer before checking hash-free typed reads.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count backend work after witnesses have already been authenticated.
let time = chapterKey(StateChapter(11))
let entropy = chapterKey(StateChapter(6))
let profile = StateProfile(cores: CoreCount(2), current: ValidatorCount(6),
  previous: ValidatorCount(6), epochSlots: EpochSlots(2))
let policy = StateChapterPolicy(items: ElementLimit(32), maxBytes: ByteLimit(4))
let entries = @[timeEntry(StateTime(42)), entropyEntry(default(StateEntropy))]
let view = globalView(entries, [time])
let missing = globalView(entries, [entropy])
let absent = globalView(@[entropyEntry(default(StateEntropy))], [time])
let malformed = globalView(@[StateEntry(key: time, value: @[byte(1), 2, 3])], [time])
let suffix = globalView(@[StateEntry(key: time, value: @[byte(1), 2, 3, 4, 5])], [time])
let plan = planProofChapters([StateChapterId.Time, StateChapterId.Entropy], ElementLimit(2)).value
assert plan.len == 2 and array[31, byte](plan.keyAt(0).value) == array[31, byte](entropy)
assert planProofChapter(StateChapterId.Time, ElementLimit(0)).error ==
    GlobalProofError.LimitExceeded
assert planProofChapters([StateChapterId.Time, StateChapterId.Time], ElementLimit(2)).error ==
    GlobalProofError.InvalidInput
assert planProofChapters([], ElementLimit(0)).value.valid
fail(1)
assert uint32(view.readGlobalTime.value) == 42
assert view.readProofChapter(StateChapterId.Time, profile, policy).error == GlobalProofError.None
assert default(ProofView).readGlobalTime.error == GlobalProofError.Uninitialized
assert missing.readGlobalTime.error == GlobalProofError.MissingWitness
assert absent.readGlobalTime.error == GlobalProofError.AbsentValue
assert malformed.readGlobalTime.error == GlobalProofError.InvalidValue
assert suffix.readGlobalTime.error == GlobalProofError.InvalidValue
assert missing.readProofChapter(StateChapterId.Time, profile, policy).error ==
    GlobalProofError.MissingWitness
assert absent.readProofChapter(StateChapterId.Time, profile, policy).error ==
    GlobalProofError.AbsentValue
assert malformed.readProofChapter(StateChapterId.Time, profile, policy).error ==
    GlobalProofError.InvalidValue
assert view.readProofChapter(StateChapterId.Time, default(StateProfile), policy).error ==
    GlobalProofError.InvalidConfig
assert view.readProofChapter(StateChapterId.Time, profile,
  StateChapterPolicy(items: ElementLimit(32), maxBytes: ByteLimit(3))).error ==
      GlobalProofError.LimitExceeded
assert suffix.readProofChapter(StateChapterId.Time, profile,
  StateChapterPolicy(items: ElementLimit(32), maxBytes: ByteLimit(5))).error ==
      GlobalProofError.InvalidValue
assert calls() == 0
fail(0)
echo "state-global-chapter-reads: ok"
