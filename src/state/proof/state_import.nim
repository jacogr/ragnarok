# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Restore an independently selected complete map from verified partial evidence only after full-map root equality proves completeness.
import ./view as proof_view
import ../[trie_proof, store]
import ../../codec/bounded
import ../../codec/state/[trie as state_trie, layout as state_layout]
type
  ProofStateImportLimits* = object ## Input lookup traversal and temporary entry copies are independent of the resulting complete store's inherited policies.
    lookups*: ElementLimit
    copyBytes*: ByteLimit
    store*: StateStoreLimits
  ProofStateImportError* {.pure.} = enum ## Partial evidence and root disagreement never become successful complete snapshots.
    Uninitialized, None, InvalidView, WrongRoot, LimitExceeded, Incomplete, StoreFailure, ConflictingEvidence
  ProofStateImportResult* = object ## No default/refused conversion exposes a partial store, candidate root or usable prefix.
    case status: ProofStateImportError
    of None: completed: StateStore
    of StoreFailure: storeReason: StateStoreError
    else: discard # Only recomputed expected-root equality grants complete-map ownership.

func error*(outcome: ProofStateImportResult): ProofStateImportError =
  ## Observe immutable conversion stages without granting their candidate storage.
  outcome.status

func value*(outcome: ProofStateImportResult): StateStore {.inline, requires: outcome.status ==
    ProofStateImportError.None.} =
  ## Extract only an independently owned complete map authenticated against the caller's expected root.
  outcome.completed

func storeFailure*(outcome: ProofStateImportResult): StateStoreError {.inline,
    requires: outcome.status == ProofStateImportError.StoreFailure.} =
  ## Preserve exact complete-store node/resource/backend refusal separately from local copy admission.
  outcome.storeReason

proc importProofState*(source: ProofView, expected: StateRoot,
    limits: ProofStateImportLimits): ProofStateImportResult =
  ## Never infer completeness from witness count or a view's own root; rebuild all present facts and compare to an independently supplied complete commitment.
  template fail(reason: ProofStateImportError) =
    return ProofStateImportResult(status: reason)
  if not source.valid: fail(ProofStateImportError.InvalidView)
  if array[32, byte](source.root) != array[32, byte](expected): fail(
      ProofStateImportError.WrongRoot)
  if uint64(source.len) > uint64(limits.lookups): fail(ProofStateImportError.LimitExceeded)
  var available = min(uint64(limits.copyBytes), uint64(high(int)))
  var valueBytes = uint64(limits.store.trie.totalValueBytes)
  var entries = 0
  for i in 0..<source.len:
    let lookup = source.lookupAt(i).value
    if lookup.present:
      if uint64(entries) >= uint64(limits.store.trie.items) or available < uint64(sizeof(StateEntry)):
        fail(ProofStateImportError.LimitExceeded) # Present-empty values consume real descriptors and map entries too.
      available -= uint64(sizeof(StateEntry))
      let size = uint64(lookup.byteLength)
      if size > uint64(limits.store.trie.perValue) or size > valueBytes or size > available:
        fail(ProofStateImportError.LimitExceeded) # Subtraction admits every copied payload before any allocation or hashing.
      valueBytes -= size
      available -= size
      inc entries # Input length already bounds the signed native counter.
  var copied = newSeq[StateEntry](entries)
  var next = 0
  for i in 0..<source.len:
    let lookup = source.lookupAt(i).value
    if lookup.present:
      copied[next] = StateEntry(key: lookup.key, value: lookup.bytes)
      inc next # Only admitted present facts contribute to a candidate complete map; absence adds no fabricated value.
  let made = newStateStore(copied, limits.store)
  if made.error != StateStoreError.None:
    return ProofStateImportResult(status: ProofStateImportError.StoreFailure,
        storeReason: made.error)
  if array[32, byte](made.value.snapshot.value.commitment.root) != array[32, byte](expected):
    fail(ProofStateImportError.Incomplete) # A valid partial view cannot substitute its witnessed subset for the original complete map.
  ProofStateImportResult(status: ProofStateImportError.None, completed: made.value)

type
  ProofPageImportLimits* = object ## All delivered lookups, including repeats and absence, are bounded separately from distinct complete-map copies.
    pages*, lookups*: ElementLimit
    scratchBytes*, copyBytes*: ByteLimit
    store*: StateStoreLimits
  PageCursor = object ## One heap slot borrows a sorted immutable page at its next unread ordinal.
    page, index: int

func compareImportKey(left, right: StateKey): int =
  ## Compare fixed serialized identities without copying values or consulting a backend.
  let a = array[31, byte](left)
  let b = array[31, byte](right)
  for i in 0..<31:
    # The first differing byte determines complete-map ordering.
    if a[i] < b[i]: return -1
    if a[i] > b[i]: return 1
  0

proc cursorBefore(left, right: PageCursor, pages: openArray[ProofView]): bool =
  ## Immutable page ordinals always name already authenticated facts.
  compareImportKey(pages[left.page].lookupAt(left.index).value.key,
      pages[right.page].lookupAt(right.index).value.key) < 0

proc siftPage(heap: var seq[PageCursor], count, start: int, pages: openArray[ProofView]) =
  ## Repair one min-heap path; the loop proves child multiplication stays within the admitted native array.
  var parent = start
  while parent < count div 2:
    # Every internal node has a left child; inspect the right child only when it exists.
    var child = parent*2+1
    if child+1 < count and cursorBefore(heap[child+1], heap[child], pages):
      inc child # Prefer the smaller existing child without reading past the active heap.
    if not cursorBefore(heap[child], heap[parent], pages): return
    swap(heap[child], heap[parent])
    parent = child

proc resetPages(heap: var seq[PageCursor], pages: openArray[ProofView]): int =
  ## Reuse one admitted scratch array for both the complete preflight and the eventual copy pass.
  var count = 0
  for i in 0..<pages.len:
    # Empty authenticated pages carry root evidence but contribute no fabricated key.
    if pages[i].len > 0:
      heap[count] = PageCursor(page: i, index: 0)
      inc count
  var next = count div 2
  while next > 0:
    # Bottom-up heap construction stays linear in the delivered page count.
    dec next
    siftPage(heap, count, next, pages)
  count

proc takePage(heap: var seq[PageCursor], count: var int,
    pages: openArray[ProofView]): VerifiedStateLookup =
  ## Consume exactly one witnessed fact and keep the remaining immutable page heads ordered.
  let cursor = heap[0]
  let lookup = pages[cursor.page].lookupAt(cursor.index).value
  if cursor.index+1 < pages[cursor.page].len:
    heap[0].index = cursor.index+1 # Input length bounds this increment before reuse.
  else:
    dec count
    heap[0] = heap[count] # Remove an exhausted page without growing scratch storage.
  if count > 0: siftPage(heap, count, 0, pages)
  lookup

proc importProofPages*(pages: openArray[ProofView], expected: StateRoot,
    limits: ProofPageImportLimits): ProofStateImportResult =
  ## Borrow stable verified pages in arbitrary arrival order; duplicates must agree and only recomputed whole-root equality grants complete ownership.
  template fail(reason: ProofStateImportError) =
    return ProofStateImportResult(status: reason)
  if uint64(pages.len) > uint64(limits.pages): fail(ProofStateImportError.LimitExceeded)
  let scratch = min(uint64(limits.scratchBytes), uint64(high(int)))
  if uint64(pages.len) > scratch div uint64(sizeof(PageCursor)):
    fail(ProofStateImportError.LimitExceeded) # Admit the entire fixed heap before allocating or retaining new aliases.
  var remaining = uint64(limits.lookups)
  for page in pages:
    # Every root and every repeated/absent lookup is admitted before scratch allocation or commitment hashing.
    if not page.valid: fail(ProofStateImportError.InvalidView)
    if array[32, byte](page.root) != array[32, byte](expected): fail(
        ProofStateImportError.WrongRoot)
    if uint64(page.len) > remaining: fail(ProofStateImportError.LimitExceeded)
    remaining -= uint64(page.len)
  var heap = newSeq[PageCursor](pages.len)
  var count = resetPages(heap, pages)
  var previous = default(VerifiedStateLookup)
  var entries = 0
  var available = min(uint64(limits.copyBytes), uint64(high(int)))
  var bytes = uint64(limits.store.trie.totalValueBytes)
  while count > 0:
    # Preflight the full sorted union before allocating any entry or copying any payload.
    let lookup = takePage(heap, count, pages)
    if previous.valid and compareImportKey(previous.key, lookup.key) == 0:
      if not sameVerifiedLookup(previous, lookup).value:
        fail(ProofStateImportError.ConflictingEvidence) # A duplicate delivery cannot overwrite authenticated facts.
    else:
      if lookup.present:
        if uint64(entries) >= uint64(limits.store.trie.items) or available < uint64(sizeof(StateEntry)):
          fail(ProofStateImportError.LimitExceeded)
        available -= uint64(sizeof(StateEntry))
        let size = uint64(lookup.byteLength)
        if size > available or size > bytes or size > uint64(limits.store.trie.perValue):
          fail(ProofStateImportError.LimitExceeded) # Subtraction protects exact distinct-value and native descriptor budgets.
        available -= size
        bytes -= size
        inc entries
      previous = lookup # Remember only the last unique immutable fact, including authenticated absence.
  var copied = newSeq[StateEntry](entries)
  count = resetPages(heap, pages)
  previous = default(VerifiedStateLookup)
  var next = 0
  while count > 0:
    # Repeat the identical ordering with stable borrowed inputs; all copies were admitted by the completed first pass.
    let lookup = takePage(heap, count, pages)
    if not previous.valid or compareImportKey(previous.key, lookup.key) != 0:
      if lookup.present:
        copied[next] = StateEntry(key: lookup.key, value: lookup.bytes)
        inc next # Present-empty remains a real complete-map entry; repeated facts consume no second copy.
      previous = lookup
  let made = newStateStore(copied, limits.store)
  if made.error != StateStoreError.None:
    return ProofStateImportResult(status: ProofStateImportError.StoreFailure,
        storeReason: made.error)
  if array[32, byte](made.value.snapshot.value.commitment.root) != array[32, byte](expected):
    fail(ProofStateImportError.Incomplete) # Neither page counts nor presence witnesses establish completeness by themselves.
  ProofStateImportResult(status: ProofStateImportError.None, completed: made.value)
