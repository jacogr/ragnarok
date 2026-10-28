# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Direct complete-state restoration covers unordered overlapping pages, exact admission, empty facts, failure recovery and retired source ownership.
import std/assertions
import std/syncio
import std/envvars
import std/cmdline
import ../support/testing_arc_evidence
import ../../src/state/proof_state_import as state_proof_state_import
import ../../src/state/proof_view as state_proof_view
import ../../src/state/trie_proof as state_trie_proof
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_layout as codec_state_layout
import ../../src/codec/state_trie as codec_state_trie
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Force genuine complete-root backend refusal after local admission has completed.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Prove whole-union resource refusal precedes commitment hashing.
const
  mapLimits = StateTrieLimits(items: ElementLimit(64), nodes: TrieNodeLimit(16384),
      perValue: ByteLimit(128), totalValueBytes: ByteLimit(8192))
  proofLimits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(128))
  batchLimits = StateProofBatchLimits(items: ElementLimit(128), nodes: ElementLimit(32768),
      valueBytes: ByteLimit(16384))
  limits = ProofPageImportLimits(pages: ElementLimit(128), lookups: ElementLimit(1024),
      scratchBytes: ByteLimit(4096), copyBytes: ByteLimit(65536), store: StateStoreLimits(
      trie: mapLimits, writes: ElementLimit(64), writeValueBytes: ByteLimit(8192)))
proc evidence(entries: seq[StateEntry], keys: seq[StateKey], root: StateRoot): ProofView =
  ## Generate independently verified page inputs with no importer construction shortcuts.
  let proofs = generateStateProofs(entries, keys, mapLimits, proofLimits, batchLimits).value
  var queries = newSeq[StateProofQuery](proofs.len)
  for i in 0..<queries.len: queries[i] = proofs.queryAt(
      i).value # Preserve exact query identities and immutable witnesses.
  captureProofView(verifyStateProofs(queries, root, proofLimits, batchLimits).value, root,
    ProofViewLimits(items: ElementLimit(128), valueBytes: ByteLimit(16384))).value
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
  var entries: seq[StateEntry] = @[]
  var keys: seq[StateKey] = @[]
  for i in 1..31:
    # Deliberately include empty and regular hashed values in a multi-level heap corpus.
    var bytes = newSeq[byte](if i mod 3 == 0: 0 else: 40)
    for j in 0..<bytes.len: bytes[j] = byte(i+j) # Literal payload pattern is independent of restoration.
    let key = chapterKey(StateChapter(i))
    entries.add(StateEntry(key: key, value: bytes))
    keys.add(key)
  let root = stateTrieRoot(entries, mapLimits).value.root
  let absent = chapterKey(StateChapter(99))
  let whole = evidence(entries, keys, root)
  var pages: seq[ProofView] = @[]
  for i in 0..<entries.len:
    # Reverse one-key pages with overlap and an absence fact exercise ties and uneven heap sizes.
    let at = entries.len-1-i
    pages.add(evidence(entries, @[keys[at], absent], root))
  pages.add(evidence(entries, @[], root))
  let repeated = pages[0]
  pages.add(repeated)
  fail(1)
  var short = limits
  short.pages = ElementLimit(uint64(pages.len-1))
  assert importProofPages(pages, root, short).error == ProofStateImportError.LimitExceeded and
      calls() == 0
  short = limits
  short.lookups = ElementLimit(63)
  assert importProofPages(pages, root, short).error == ProofStateImportError.LimitExceeded and
      calls() == 0
  short = limits
  short.scratchBytes = ByteLimit(uint64(pages.len*2*sizeof(int)-1))
  assert importProofPages(pages, root, short).error == ProofStateImportError.LimitExceeded and
      calls() == 0
  short = limits
  short.copyBytes = ByteLimit(uint64(entries.len*sizeof(StateEntry)+21*40-1))
  assert importProofPages(pages, root, short).error == ProofStateImportError.LimitExceeded and
      calls() == 0
  short = limits
  short.store.trie.items = ElementLimit(30)
  assert importProofPages(pages, root, short).error == ProofStateImportError.LimitExceeded and
      calls() == 0
  short = limits
  short.store.trie.perValue = ByteLimit(39)
  assert importProofPages(pages, root, short).error == ProofStateImportError.LimitExceeded and
      calls() == 0
  short = limits
  short.store.trie.totalValueBytes = ByteLimit(839)
  assert importProofPages(pages, root, short).error == ProofStateImportError.LimitExceeded and
      calls() == 0
  assert importProofPages([default(ProofView)], root, limits).error ==
      ProofStateImportError.InvalidView
  assert importProofPages([whole], default(StateRoot), limits).error ==
      ProofStateImportError.WrongRoot
  assert importProofPages(pages, root, limits).storeFailure == StateStoreError.BackendFailure
  fail(0)
  short = limits
  short.scratchBytes = ByteLimit(uint64(pages.len*2*sizeof(int)))
  short.copyBytes = ByteLimit(uint64(entries.len*sizeof(StateEntry)+21*40))
  short.lookups = ElementLimit(64)
  short.store.trie.items = ElementLimit(31)
  short.store.trie.totalValueBytes = ByteLimit(840)
  let restored = importProofPages(pages, root, short).value.snapshot.value
  assert array[32, byte](restored.commitment.root) == array[32, byte](root)
  assert restored.commitment.entries == entries.len
  for entry in entries:
    assert restored.lookup(entry.key).value.bytes ==
        entry.value # Compare every original value including present-empty.
  assert restored.lookup(absent).error == StateStoreError.MissingKey
  assert importProofPages([pages[0]], root, limits).error == ProofStateImportError.Incomplete
  let emptyRoot = stateTrieRoot([], mapLimits).value.root
  assert importProofPages([], emptyRoot, limits).value.snapshot.value.commitment.entries == 0
  assert importProofPages([], root, limits).error == ProofStateImportError.Incomplete
  for width in 1..31:
    # All heap sizes and changing sorted overlap patterns must reconstruct the same literal full map.
    var selected: seq[ProofView] = @[]
    for i in 0..<width: selected.add(pages[i])
    selected.add(whole)
    assert importProofPages(selected, root, limits).value.snapshot.value.commitment.entries == 31
  pages = @[]
  entries[0].value[0] = 255
  assert restored.lookup(keys[0]).value.bytes[0] == 1
  let stable = @[whole, whole]
  for i in 0..<25: discard importProofPages(stable, root,
      limits).value # Warm the exact isolated repeated-page retirement path.
  let before = getOccupiedMem()
  for i in 0..<1000: discard importProofPages(stable, root, limits).value
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_proof_page_import", 1000, before, after)
  echo "state-proof-page-import: ok"
try:
  main()
except:
  quit(2) # Unexpected setup failure cannot masquerade as a guarded accessor rejection.
