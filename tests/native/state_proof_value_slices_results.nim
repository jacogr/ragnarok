# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticated value slices admit only exact owner-bound ranges; overlapping view merges compare immutable facts without whole-payload copies.
import std/assertions
import std/syncio
import std/envvars
import std/cmdline
import ../support/testing_arc_evidence
import ../../src/state/trie_proof as state_trie_proof
import ../../src/state/proof_view as state_proof_view
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reading/comparing already authenticated immutable values needs no further crypto backend work.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe zero crypto work across slice/range and duplicate-union operations.
const mapLimits = StateTrieLimits(items: ElementLimit(8), nodes: TrieNodeLimit(1024),
    perValue: ByteLimit(131072), totalValueBytes: ByteLimit(262144))
const perProof = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(131072))
const batchLimits = StateProofBatchLimits(items: ElementLimit(8), nodes: ElementLimit(1992),
    valueBytes: ByteLimit(262144))
const viewLimits = ProofViewLimits(items: ElementLimit(8), valueBytes: ByteLimit(262144))
proc viewOf(entries: seq[StateEntry], keys: seq[StateKey], root: StateRoot): ProofView =
  ## Authenticate independently captured immutable witnesses before testing value-copy or equality behavior.
  let proofs = generateStateProofs(entries, keys, mapLimits, perProof, batchLimits).value
  var queries = newSeq[StateProofQuery](proofs.len)
  for i in 0..<queries.len: queries[i] = proofs.queryAt(i).value
  captureProofView(verifyStateProofs(queries, root, perProof, batchLimits).value, root,
      viewLimits).value
proc escaped(): VerifiedStateLookup =
  ## Retain only a successful lookup after all original source/proof/view containers have left scope.
  let key = chapterKey(StateChapter(1))
  let entries = @[StateEntry(key: key, value: @[8'u8, 9, 10])]
  viewOf(entries, @[key], stateTrieRoot(entries, mapLimits).value.root).lookup(key).value
proc cycle(a, b: ProofView, value: VerifiedStateLookup) =
  ## Each cycle releases detached interval bytes and a duplicate union while both immutable input owners remain unchanged.
  assert value.copySlice(65535, 4, ByteLimit(4)).value == @[255'u8, 0, 1, 2]
  assert value.copySlice(high(uint64), 1, ByteLimit(high(uint64))).error ==
      StateProofError.InvalidRange
  assert sameVerifiedLookup(value, value).value
  assert mergeProofViews(a, b, viewLimits).value.len == 3
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(StateProofResult[seq[byte]])
  if mode == "value":
    discard empty.value
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  var payload = newSeq[byte](131072)
  for i in 0..<payload.len: payload[i] = byte(i mod 256) # Large authenticated payload and independent literal crossing-boundary bytes expose whole-value/truncation mistakes.
  let first = chapterKey(StateChapter(1))
  let second = chapterKey(StateChapter(2))
  let absent = chapterKey(StateChapter(9))
  let entries = @[StateEntry(key: first, value: payload), StateEntry(key: second, value: @[])]
  let root = stateTrieRoot(entries, mapLimits).value.root
  let a = viewOf(entries, @[first, second, absent], root)
  let b = viewOf(entries, @[absent, first], root)
  let large = a.lookup(first).value
  let zero = a.lookup(second).value
  let missing = a.lookup(absent).value
  let otherEntries = @[StateEntry(key: first, value: @[8'u8])]
  let other = viewOf(otherEntries, @[first], stateTrieRoot(otherEntries,
      mapLimits).value.root).lookup(first).value
  fail(1)
  assert default(VerifiedStateLookup).copySlice(0, 0, ByteLimit(0)).error ==
      StateProofError.Uninitialized
  assert missing.copySlice(0, 0, ByteLimit(0)).error == StateProofError.MissingValue
  assert zero.copySlice(0, 0, ByteLimit(0)).value.len == 0
  assert zero.copySlice(0, 1, ByteLimit(1)).error == StateProofError.InvalidRange
  assert large.copySlice(131072, 0, ByteLimit(0)).value.len == 0
  assert large.copySlice(131073, 0, ByteLimit(high(uint64))).error == StateProofError.InvalidRange
  assert large.copySlice(high(uint64), high(uint64), ByteLimit(high(uint64))).error ==
      StateProofError.InvalidRange
  assert large.copySlice(131071, 2, ByteLimit(2)).error == StateProofError.InvalidRange
  assert large.copySlice(65535, 4, ByteLimit(3)).error == StateProofError.LimitExceeded
  var slice = large.copySlice(65535, 4, ByteLimit(4)).value
  assert slice == @[255'u8, 0, 1, 2]
  slice[0] = 42
  assert large.copySlice(65535, 4, ByteLimit(high(uint64))).value == @[255'u8, 0, 1, 2]
  assert sameVerifiedLookup(default(VerifiedStateLookup), large).error ==
      StateProofError.Uninitialized
  assert sameVerifiedLookup(large, default(VerifiedStateLookup)).error ==
      StateProofError.Uninitialized
  assert sameVerifiedLookup(large, b.lookup(first).value).value
  assert sameVerifiedLookup(missing, b.lookup(absent).value).value
  assert not sameVerifiedLookup(large, zero).value and not sameVerifiedLookup(large, other).value
  assert not sameVerifiedLookup(zero, missing).value
  var exact = viewLimits
  exact.items = ElementLimit(3)
  exact.valueBytes = ByteLimit(131072)
  assert mergeProofViews(a, b, exact).value.len == 3
  exact.valueBytes = ByteLimit(131071)
  assert mergeProofViews(a, b, exact).error == ProofViewError.LimitExceeded
  assert large.copySlice(0, 131072, ByteLimit(131072)).value == payload
  assert calls() == 0
  fail(0)
  assert escaped().copySlice(1, 2, ByteLimit(2)).value == @[9'u8, 10]
  for i in 0..<25: cycle(a, b, large) # Warm only this pure host-owned lookup/union/copy path.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(a, b, large) # Exact net retained ownership is measured without native worker allocator attribution.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_proof_value_slices", 1000, before, after)
  echo "state-proof-value-slices: ok"
try:
  main()
except:
  quit(2) # Ordinary source/crypto refusal never satisfies strict result extraction rejection.
