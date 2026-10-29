# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full, partial, absent and present-empty authenticated views exercise the checked completeness boundary and independent copy/store policies.
import std/[assertions, syncio, envvars, cmdline]
import ../support/arc_evidence
import ../../src/state/proof/[state_import as proof_state_import, view as proof_view]
import ../../src/state/[trie_proof, store]
import ../../src/codec/bounded
import ../../src/codec/state/[layout as state_layout, trie as state_trie]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Genuine root-construction refusal cannot become a successful complete import.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Whole-view copy admission precedes all commitment hashing.
const
  mapLimits = StateTrieLimits(items: ElementLimit(8), nodes: TrieNodeLimit(4096),
      perValue: ByteLimit(128), totalValueBytes: ByteLimit(512))
  proofLimits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(128))
  batchLimits = StateProofBatchLimits(items: ElementLimit(16), nodes: ElementLimit(4096),
      valueBytes: ByteLimit(512))
  importLimits = ProofStateImportLimits(lookups: ElementLimit(4), copyBytes: ByteLimit(4096),
      store: StateStoreLimits(trie: mapLimits, writes: ElementLimit(8), writeValueBytes: ByteLimit(512)))
proc evidence(entries: seq[StateEntry], keys: seq[StateKey], root: StateRoot): ProofView =
  ## Generate and independently verify each selected witness before the conversion under test sees its immutable view.
  let proofs = generateStateProofs(entries, keys, mapLimits, proofLimits, batchLimits).value
  var queries = newSeq[StateProofQuery](proofs.len)
  for i in 0..<queries.len: queries[i] = proofs.queryAt(
      i).value # Copy only immutable proof owners with their exact requested identities.
  captureProofView(verifyStateProofs(queries, root, proofLimits, batchLimits).value, root,
    ProofViewLimits(items: ElementLimit(16), valueBytes: ByteLimit(512))).value
proc escaped(): StateStore =
  ## Retire original values, proof objects and verified views before using the independently owned imported map.
  let entries = @[StateEntry(key: chapterKey(StateChapter(1)), value: @[7'u8])]
  let root = stateTrieRoot(entries, mapLimits).value.root
  importProofState(evidence(entries, @[entries[0].key], root), root, importLimits).value
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(ProofStateImportResult)
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.storeFailure
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  var longValue = newSeq[byte](40)
  for i in 0..<longValue.len: longValue[i] = byte(
      i) # Exercise hashed regular-leaf values beyond the embedded-leaf threshold.
  var entries = @[StateEntry(key: chapterKey(StateChapter(1)), value: @[7'u8]),
    StateEntry(key: chapterKey(StateChapter(2)), value: @[]),
    StateEntry(key: chapterKey(StateChapter(3)), value: longValue)]
  let root = stateTrieRoot(entries, mapLimits).value.root
  let absent = chapterKey(StateChapter(9))
  var whole = evidence(entries, @[entries[2].key, absent, entries[0].key, entries[1].key], root)
  let partial = evidence(entries, @[entries[0].key, absent], root)
  let omitEmpty = evidence(entries, @[entries[0].key, entries[2].key], root)
  let noEvidence = evidence(entries, @[], root)
  fail(1)
  var short = importLimits
  short.lookups = ElementLimit(3)
  assert importProofState(whole, root, short).error == ProofStateImportError.LimitExceeded and
      calls() == 0
  short = importLimits
  short.store.trie.items = ElementLimit(2)
  assert importProofState(whole, root, short).error == ProofStateImportError.LimitExceeded and
      calls() == 0
  short = importLimits
  short.store.trie.perValue = ByteLimit(39)
  assert importProofState(whole, root, short).error == ProofStateImportError.LimitExceeded and
      calls() == 0
  short = importLimits
  short.store.trie.totalValueBytes = ByteLimit(40)
  assert importProofState(whole, root, short).error == ProofStateImportError.LimitExceeded and
      calls() == 0
  short = importLimits
  short.copyBytes = ByteLimit(uint64(sizeof(StateEntry)*3+40))
  assert importProofState(whole, root, short).error == ProofStateImportError.LimitExceeded and
      calls() == 0
  assert importProofState(default(ProofView), root, importLimits).error ==
      ProofStateImportError.InvalidView
  assert importProofState(whole, default(StateRoot), importLimits).error ==
      ProofStateImportError.WrongRoot and calls() == 0
  assert importProofState(whole, root, importLimits).storeFailure == StateStoreError.BackendFailure
  fail(0)
  short = importLimits
  short.copyBytes = ByteLimit(uint64(sizeof(StateEntry)*3+41))
  short.store.trie.items = ElementLimit(3)
  short.store.trie.perValue = ByteLimit(40)
  short.store.trie.totalValueBytes = ByteLimit(41)
  var restored = importProofState(whole, root, short).value
  let retained = restored.snapshot.value
  assert retained.commitment.entries == 3 and array[32, byte](retained.commitment.root) == array[32,
      byte](root)
  for entry in entries: assert retained.lookup(entry.key).value.bytes ==
      entry.value # Compare every actual present value, including empty bytes and a regular hashed leaf.
  assert retained.lookup(absent).error == StateStoreError.MissingKey
  var noNodes = importLimits
  noNodes.store.trie.nodes = TrieNodeLimit(0)
  assert importProofState(whole, root, noNodes).storeFailure == StateStoreError.LimitExceeded
  assert importProofState(partial, root, importLimits).error == ProofStateImportError.Incomplete
  assert importProofState(omitEmpty, root, importLimits).error == ProofStateImportError.Incomplete
  assert importProofState(noEvidence, root, importLimits).error == ProofStateImportError.Incomplete
  entries[0].value[0] = 0
  whole = default(ProofView)
  assert retained.lookup(chapterKey(StateChapter(1))).value.bytes == @[7'u8]
  let changed = restored.apply([StateWrite(key: chapterKey(StateChapter(1)),
      kind: StateWriteKind.Put, value: @[8'u8])])
  assert changed.error == StateStoreError.None
  assert retained.lookup(chapterKey(StateChapter(1))).value.bytes == @[
      7'u8] # Independent writes preserve both original proof values and retained imported versions.
  assert restored.apply([StateWrite(key: absent, kind: StateWriteKind.Put, value: @[])]).error ==
      StateStoreError.LimitExceeded
  let emptyRoot = stateTrieRoot([], mapLimits).value.root
  let emptyView = evidence(@[], @[absent], emptyRoot)
  assert importProofState(emptyView, emptyRoot, importLimits).value.snapshot.value.commitment.entries == 0
  assert escaped().snapshot.value.lookup(chapterKey(StateChapter(1))).value.bytes == @[7'u8]
  let stable = evidence(@[StateEntry(key: absent, value: @[1'u8])], @[absent], stateTrieRoot([
      StateEntry(key: absent, value: @[1'u8])], mapLimits).value.root)
  for i in 0..<25: discard importProofState(stable, stable.root,
      importLimits).value # Warm this exact isolated map reconstruction/retirement path.
  let before = getOccupiedMem()
  for i in 0..<1000: discard importProofState(stable, stable.root, importLimits).value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_proof_state_import", 1000, before, after)
  echo "state-proof-state-import: ok"
try:
  main()
except:
  quit(2) # Ordinary fixture/source refusal cannot masquerade as a guarded result failure.
