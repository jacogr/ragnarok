# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit bounded guarantor serving storage never evicts a signed source to admit later work.
## Services owns this cache and freezes every alias through exact worker collection or joined shutdown.
import ./availability_proof
import ../codec/bounded
from ../codec/work/report import ErasureRoot
import ../state/availability/specifier

const MaxGuarantorEntries = 64 ## Fixed metadata stays independent of original bundle and validator-population payload sizes.
type
  GuarantorStorageLimits* = object ## Computation bytes bound the whole cache plus capture workspace; hashes bound each new complete capture.
    entries*: ElementLimit
    computation*: AvailabilityMerkleLimits
  GuarantorStoreError* {.pure.} = enum ## Defaults and refusals never expose an absent or partially retained source.
    Uninitialized, None, Unconfigured, InvalidSource, Missing, Conflict, LimitExceeded
  GuarantorStoreResult* = object ## Only exact-root success exposes a genuine immutable source-free serving owner.
    case status: GuarantorStoreError
    of None: completed: GuarantorAvailability
    else: discard # No failed lookup carries an all-zero successful bundle.
  GuarantorEntry = object ## Fixed root/size metadata accompanies one complete immutable source-free snapshot.
    specifier: AvailabilitySpecifier
    source: GuarantorAvailability
  GuarantorStore* = object ## Caller must retire all worker aliases before shutdown; there is no automatic live eviction or retention timeout.
    ready: bool
    limits: GuarantorStorageLimits
    entries: array[MaxGuarantorEntries, GuarantorEntry]
    count: int
    bytes: uint64
func error*(outcome: GuarantorStoreResult): GuarantorStoreError =
  ## Select a complete lookup only after observing this private reason.
  outcome.status
func value*(outcome: GuarantorStoreResult): GuarantorAvailability {.requires: outcome.status ==
    GuarantorStoreError.None.} =
  ## A retained serving source confers neither assurance nor canonical report admission.
  outcome.completed
func valid*(limits: GuarantorStorageLimits): bool =
  ## Defaults cannot enable signed-source storage or borrow unbounded capture work.
  uint64(limits.entries) > 0 and uint64(limits.entries) <= uint64(MaxGuarantorEntries) and
    limits.computation.validGuarantorLimits
func configured*(store: GuarantorStore): bool =
  ## Scalar configuration observation does not touch a frozen source owner.
  store.ready
func matches*(store: GuarantorStore, limits: GuarantorStorageLimits): bool =
  ## Reopening an existing host may reuse only its original explicit storage and capture ceilings.
  store.ready and uint64(store.limits.entries) == uint64(limits.entries) and
    uint64(store.limits.computation.bytes) == uint64(limits.computation.bytes) and
    uint64(store.limits.computation.hashes) == uint64(limits.computation.hashes) and
    uint64(store.limits.computation.hashBytes) == uint64(limits.computation.hashBytes)
func len*(store: GuarantorStore): int =
  ## A fixed counter is independent of any worker's immutable serving aliases.
  store.count
func byteLength*(store: GuarantorStore): uint64 =
  ## Logical retained payload excludes bounded metadata and allocator bookkeeping.
  store.bytes
proc configure*(store: var GuarantorStore, limits: GuarantorStorageLimits): bool =
  ## Validate once before signing begins; a live policy cannot be rebound or silently erase earlier reports.
  if store.ready or not limits.valid: return false
  store.limits = limits
  store.ready = true
  true
proc clear*(store: var GuarantorStore) =
  ## Explicit shutdown only: the owner must first join or exactly collect every worker borrowing stored sources.
  store = default(GuarantorStore)
func captureLimits*(store: GuarantorStore): AvailabilityMerkleLimits =
  ## Inspect free entry and whole-cache bytes before signing admission; Services must keep this budget stable through collection.
  if not store.ready or uint64(store.count) >= uint64(store.limits.entries):
    return default(AvailabilityMerkleLimits)
  result = store.limits.computation
  result.bytes = ByteLimit(uint64(store.limits.computation.bytes)-store.bytes)
func sameSpecifier(left, right: AvailabilitySpecifier): bool =
  ## Equal root bytes cannot replace independently selected package, bundle, export or validator geometry.
  left.packageHash.bytes == right.packageHash.bytes and
    left.erasureRoot.bytes == right.erasureRoot.bytes and
    left.segmentRoot.bytes == right.segmentRoot.bytes and
    uint32(left.bundleLength) == uint32(right.bundleLength) and
    uint16(left.erasureShards) == uint16(right.erasureShards) and
    uint16(left.segmentCount) == uint16(right.segmentCount)
proc remember*(store: var GuarantorStore, source: GuarantorAvailability): GuarantorStoreError =
  ## Call only after exact collection; every refusal precedes mutation and no later report displaces a promised source.
  if not store.ready: return GuarantorStoreError.Unconfigured
  let described = source.guarantorInfo
  if described.error != AvailabilityTransferError.None: return GuarantorStoreError.InvalidSource
  let info = described.value
  for index in 0..<store.count:
    # An already retained exact commitment needs no new capacity or mutation of its shared byte owners.
    if store.entries[index].specifier.erasureRoot.bytes !=
        info.specifier.erasureRoot.bytes: continue
    if not sameSpecifier(store.entries[index].specifier,
        info.specifier): return GuarantorStoreError.Conflict
    return GuarantorStoreError.None
  if uint64(store.count) >= uint64(store.limits.entries): return GuarantorStoreError.LimitExceeded
  if info.retainedBytes > uint64(store.limits.computation.bytes)-store.bytes:
    return GuarantorStoreError.LimitExceeded
  store.entries[store.count] = GuarantorEntry(specifier: info.specifier, source: source)
  inc store.count # Configured bounds prove the fixed entry index and increment above.
  store.bytes += info.retainedBytes
  GuarantorStoreError.None
proc snapshot*(store: GuarantorStore): seq[GuarantorAvailability] =
  ## Services captures at most sixty-four private immutable byte owners, retiring temporary table aliases before the worker lease begins.
  result = newSeq[GuarantorAvailability](store.count)
  for index in 0..<store.count: result[index] = store.entries[index].source
proc find*(store: GuarantorStore, root: ErasureRoot): GuarantorStoreResult =
  ## Exact-root lookup never updates LRU counters or drops a source while another operation might borrow it.
  if not store.ready: return GuarantorStoreResult(status: GuarantorStoreError.Unconfigured)
  for index in 0..<store.count:
    if store.entries[index].specifier.erasureRoot.bytes == root.bytes:
      return GuarantorStoreResult(status: GuarantorStoreError.None, completed: store.entries[index].source)
  GuarantorStoreResult(status: GuarantorStoreError.Missing)
