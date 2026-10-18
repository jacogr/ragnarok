# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Published authentication against immutable parent/staged maps before entropy publication; no
## state mutation or trust in staged entropy.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/state/[safrole_authentication, authentication_state, entropy, store]
import ../../../src/codec/[state_safrole, state_consensus, state_layout, state_trie, header, bounded]
import ../../support/validator_rotation_fixture

## Control ordinary-verification refusal independently of map construction hashes.
proc reset(flags: cint) {.importc: "bo_reset", cdecl.}
## Refuse the seal or entropy verification after an exact successful prefix.
proc refuseAfter(successful: cint) {.importc: "bo_ietf_after", cdecl.}
## Prove malformed/preflight paths cannot reach the Rust primitive.
proc verifications(): cint {.importc: "bo_ietf_calls", cdecl.}
## Refuse any new store/hash work after immutable fixture maps have been constructed.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
## Count attempted store/hash work on both success and refusal.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}

## Parse a whole trusted unsigned decimal fixture field before narrowing.
proc number(text: string): uint64 =
  var value = 0'u64
  assert parseBiggestUInt(text, value) == text.len
  value

## Decode exact trusted hexadecimal transport without calling a production parser.
proc unhex(text: string): seq[byte] =
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var value = 0'u8
    assert parseHex(text[2*i..2*i+1], value) == 2 # Every supplied octet is complete.
    result[i] = value

## Append one explicit suffix byte without changing the original trusted fixture buffer.
proc suffixed(raw: seq[byte]): seq[byte] =
  result = newSeq[byte](raw.len+1)
  for i in 0..<raw.len: result[i] = raw[i] # Preserve every original byte before the extra trailing value.
  result[raw.len] = 0

## Tiny policy bounds chapter/roster and complete header storage independently.
proc policy(): SafroleAuthConfig =
  SafroleAuthConfig(state: SafroleStateConfig(validators: rotationRosterConfig(2),
    epochSlots: EpochSlots(12), maxAccumulator: ElementLimit(12), maxBytes: ByteLimit(100000)),
    maxHeaderBytes: ByteLimit(100000))

## Capture one exact complete signed header while allowing the structural author ceiling to differ from actual population.
proc capture(raw: seq[byte], config: SafroleAuthConfig, cores = 2): OwnedHeader =
  let parsed = decodeHeader(raw, HeaderConfig(cores: CoreCount(uint64(cores)),
    authorValidators: ValidatorCount(uint64(cores)*3), epochSlots: config.state.epochSlots,
    maxBytes: ByteLimit(100000)))
  assert parsed.error == HeaderError.None and parsed.value.consumed == raw.len
  parsed.value.owner

## Encode a complete owned header to prove the result retains the exact authenticated source, not detached fields.
proc fullBytes(owner: OwnedHeader): seq[byte] =
  result = newSeq[byte](100000)
  let written = encodeOwnedHeader(owner, result)
  assert written.error == HeaderError.None
  result.setLen(written.value)

## Complete sample-map construction has independent finite budgets, including unrelated retained state.
proc limits(): StateStoreLimits =
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(5), perValue: ByteLimit(100000),
    totalValueBytes: ByteLimit(200000), nodes: TrieNodeLimit(1000)),
    writes: ElementLimit(2), writeValueBytes: ByteLimit(100000))

## Check every original entry and root, including chapters intentionally irrelevant to pre-entropy authentication.
proc unchanged(snapshot: StateStoreSnapshot, source: seq[StateEntry], root: StateRoot) =
  assert array[32, byte](snapshot.commitment.root) == array[32, byte](root)
  for entry in source:
    assert snapshot.lookup(entry.key).value.bytes ==
        entry.value # No C(4), active roster, fixed history/time or unrelated write is allowed.

## Damage each required parent/staged chapter independently and preserve exact failure reasons and historical maps.
proc damage(before, after: seq[StateEntry], header: OwnedHeader, config: SafroleAuthConfig) =
  for parentSide in 0..<2:
    let original = if parentSide == 1: before else: after
    for index in 0..<2:
      for kind in 0..<3:
        var broken = newSeq[StateEntry](0)
        for i, entry in original:
          if i != index or kind != 0:
            var copied = StateEntry(key: entry.key, value: entry.value)
            if i == index:
              if kind == 1:
                copied.value.setLen(copied.value.len-1) # Truncated state cannot provide an all-zero default input.
              else:
                copied.value.add 0 # Exact chapter consumption rejects an ignored suffix.
            broken.add copied
        failHash(0)
        let parent = newStateStore((if parentSide == 1: broken else: before), limits()).value.snapshot.value
        let staged = newStateStore((if parentSide == 0: broken else: after), limits()).value.snapshot.value
        let oldRoot = parent.commitment.root
        let stagedRoot = staged.commitment.root
        reset(0)
        failHash(1)
        let outcome = authenticateSafroleHeaderState(parent, staged, header, config)
        assert outcome.error == (if kind == 0: SafroleAuthError.MissingState else: SafroleAuthError.InvalidState)
        assert verifications() == 0 and hashes() == 0
        unchanged(parent, (if parentSide == 1: broken else: before), oldRoot)
        unchanged(staged, (if parentSide == 0: broken else: after), stagedRoot)
  failHash(0)

## Every selected published credential authenticates with stale/absent staged entropy/time, then feeds real atomic advancement.
proc published(text: string) =
  let lines = text.splitLines()
  assert lines.len == 21
  let config = policy()
  for i in 0..<20:
    let f = lines[i].splitWhitespace()
    assert f.len == 7
    let header = capture(unhex(f[1]), config)
    let before = @[
      StateEntry(key: chapterKey(StateChapter(6)), value: unhex(f[3])),
      StateEntry(key: chapterKey(StateChapter(11)), value: unhex(f[2])),
      StateEntry(key: chapterKey(StateChapter(1)), value: @[12'u8, 34])]
    let after = @[
      StateEntry(key: chapterKey(StateChapter(4)), value: unhex(f[4])),
      StateEntry(key: chapterKey(StateChapter(8)), value: unhex(f[5])),
      StateEntry(key: chapterKey(StateChapter(6)), value: @[255'u8]),
      StateEntry(key: chapterKey(StateChapter(11)), value: @[254'u8]),
      StateEntry(key: chapterKey(StateChapter(1)), value: @[56'u8, 78])]
    failHash(0)
    var parentStore = newStateStore(before, limits()).value
    var working = newStateStore(after, limits()).value
    let parent = parentStore.snapshot.value
    let staged = working.snapshot.value
    let oldRoot = parent.commitment.root
    let stagedRoot = staged.commitment.root
    reset(0)
    failHash(1)
    let outcome = authenticateSafroleHeaderState(parent, staged, header, config)
    assert outcome.error == SafroleAuthError.None and verifications() == 2 and hashes() == 0
    unchanged(parent, before, oldRoot)
    unchanged(staged, after, stagedRoot)
    for prefix in [0, 1]:
      reset(0)
      refuseAfter(cint(prefix))
      assert authenticateSafroleHeaderState(parent, staged, header, config).error ==
          SafroleAuthError.BackendFailure
      assert verifications() == cint(prefix+1) and hashes() == 0
      unchanged(parent, before, oldRoot)
      unchanged(staged, after, stagedRoot)
    reset(0)
    assert authenticateSafroleHeaderState(default(StateStoreSnapshot), staged, header,
        config).error == SafroleAuthError.Uninitialized
    assert authenticateSafroleHeaderState(parent, default(StateStoreSnapshot), header,
        config).error == SafroleAuthError.Uninitialized
    assert authenticateSafroleHeaderState(parent, staged, default(OwnedHeader), config).error ==
        SafroleAuthError.InvalidHeader
    assert verifications() == 0 and hashes() == 0
    for kind in 0..<2:
      var small = config
      if kind == 0:
        small.state.maxBytes = ByteLimit(uint64(after[0].value.len-1)) # Posterior schedule preflight.
      else:
        small.state.validators.maxBytes = ByteLimit(uint64(after[
            1].value.len-1)) # Posterior active roster preflight.
      assert authenticateSafroleHeaderState(parent, staged, header, small).error ==
          SafroleAuthError.LimitExceeded
      assert verifications() == 0 and hashes() == 0
    failHash(0)
    if i == 0: damage(before, after, header, config) # Required chapter shape errors are independent of signature validity.
    # A pre-entropy working map can omit C(6)/C(11); the authenticated output then advances a correctly staged map atomically.
    let ready = @[after[0], after[1], before[0], before[1], after[4]]
    working = newStateStore(ready, limits()).value
    let target = StateTime(uint32(headerInfo(outcome.value.header).value.unsigned.slot))
    let advanced = advanceEntropyTimeState(working, target, outcome.value.entropy, EpochSlots(12))
    assert advanced.error == EntropyTransitionError.None
    assert advanced.value.lookup(before[0].key).value.bytes == unhex(f[6])
    assert advanced.value.lookup(before[1].key).value.bytes == timeEntry(target).value
    for entry in [after[0], after[1], after[4]]:
      assert advanced.value.lookup(entry.key).value.bytes ==
          entry.value # Real entropy/time publication changes only its two fixed chapters.
    let minimal = @[after[0], after[1], after[4]]
    working = newStateStore(minimal, limits()).value
    assert authenticateSafroleHeaderState(parent, working.snapshot.value, header, config).error ==
        SafroleAuthError.None
    parentStore = default(StateStore)
    working = default(StateStore)
    assert fullBytes(outcome.value.header) == unhex(f[
        1]) # Authenticated exact header and retained maps outlive all store handles.
    unchanged(parent, before, oldRoot)
    unchanged(staged, after, stagedRoot)
  reset(0)
  failHash(0)

try:
  published(readFile(getEnv("RAGNAROK_SAFROLE_AUTHENTICATION"))) # Missing/changed public credentials must fail preparation, never reduce coverage.
except:
  quit(2) # No partial credential corpus is accepted as a completed context suite.
echo "PASS Safrole auth state: twenty published contexts, pre-entropy ordering and immutable rollback"
