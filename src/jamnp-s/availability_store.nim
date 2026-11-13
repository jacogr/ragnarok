# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded private detached storage accepts only complete authenticated CE137 distributions; it confers no assurance duty.

import ./availability_proof
import ../codec/bounded
import ../state/availability/specifier

const MaxAvailabilityEntries = 64 ## Fixed small metadata storage never scales the caller's stack with shard payload geometry.

type
  AvailabilityStoreLimits* = object ## Explicit logical retained payload and entry ceilings never enable storage by default.
    entries*: ElementLimit
    bytes*: ByteLimit
  AvailabilityStoreError* {.pure.} = enum ## Misses/refusals contain no accepted payload or partial replacement.
    Uninitialized, None, Unconfigured, Missing, InvalidTransfer, Conflict, LimitExceeded, Exhausted, Busy
  AvailabilityStoreResult* = object ## Private successful lookup exposes only one complete verified capability.
    case status: AvailabilityStoreError
    of None: completed: VerifiedAvailabilityTransfer
    else: discard # Failed/default lookups do not expose an empty successful transfer.
  Entry = object ## Private immutable data and copied root/shard identity survive bounded replacement.
    used: bool
    age, bytes: uint64
    transfer: VerifiedAvailabilityTransfer
  AvailabilityStore* = object ## Services freezes all private entries through exact CPU collection or joined retirement.
    configured: bool
    limits: AvailabilityStoreLimits
    entries: array[MaxAvailabilityEntries, Entry]
    count: int
    bytes, next: uint64

func error*(outcome: AvailabilityStoreResult): AvailabilityStoreError =
  ## Inspect the private status before selecting a capability.
  outcome.status

func value*(outcome: AvailabilityStoreResult): VerifiedAvailabilityTransfer {.requires: outcome.status ==
    AvailabilityStoreError.None.} =
  ## A successful lookup does not transfer assurance, chain or signing authority.
  outcome.completed

func len*(store: AvailabilityStore): int =
  ## Scalar accounting remains available without borrowing any entry owner.
  store.count

func byteLength*(store: AvailabilityStore): uint64 =
  ## Count retained payload bytes independently of allocator bookkeeping and metadata.
  store.bytes

proc clear*(store: var AvailabilityStore) =
  ## The caller must retire the managed CPU lease before dropping private shared entries.
  store = default(AvailabilityStore)

proc configure*(store: var AvailabilityStore, limits: AvailabilityStoreLimits): bool =
  ## One explicit policy bounds all later replacement; a live policy cannot be rebound.
  if store.configured or uint64(limits.entries) < 1 or uint64(limits.entries) > uint64(
      MaxAvailabilityEntries): return false
  if uint64(limits.bytes) < 1 or uint64(limits.bytes) > 64'u64*1024*1024: return false
  store.limits = limits
  store.configured = true
  true

func sameSpecifier(a, b: AvailabilitySpecifier): bool =
  ## Duplicate roots cannot silently replace independently selected package, geometry or export context.
  a.packageHash.bytes == b.packageHash.bytes and a.erasureRoot.bytes == b.erasureRoot.bytes and
    a.segmentRoot.bytes == b.segmentRoot.bytes and uint32(a.bundleLength) == uint32(
        b.bundleLength) and
    uint16(a.erasureShards) == uint16(b.erasureShards) and uint16(a.segmentCount) == uint16(b.segmentCount)

func oldestEntry(store: AvailabilityStore, removed: array[MaxAvailabilityEntries, bool]): int =
  ## Select the oldest retained entry outside the staged eviction set.
  var oldest = -1
  for index in 0..<MaxAvailabilityEntries:
    if store.entries[index].used and not removed[index]:
      if oldest < 0 or store.entries[index].age < store.entries[oldest].age: oldest = index
  oldest

proc remember*(store: var AvailabilityStore, transfer: VerifiedAvailabilityTransfer): AvailabilityStoreError =
  ## Preflight all refusals before cloning or eviction; private clones isolate external ARC lifetimes from later workers.
  if not store.configured: return AvailabilityStoreError.Unconfigured
  if not transfer.valid: return AvailabilityStoreError.InvalidTransfer
  let request = transfer.request
  if request.kind != AvailabilityTransferKind.Distribution: return AvailabilityStoreError.InvalidTransfer
  let bytes = transfer.payloadBytes
  if bytes > uint64(store.limits.bytes): return AvailabilityStoreError.LimitExceeded
  if store.next == high(uint64): return AvailabilityStoreError.Exhausted
  for index in 0..<MaxAvailabilityEntries:
    if not store.entries[index].used: continue
    let previous = store.entries[index].transfer.request
    if previous.root.bytes == request.root.bytes and uint64(previous.shard) == uint64(request.shard):
      if not sameSpecifier(store.entries[index].transfer.specifier,
          transfer.specifier): return AvailabilityStoreError.Conflict
      inc store.next
      store.entries[index].age = store.next
      return AvailabilityStoreError.None # Identical authenticated content keeps the private original; no duplicate payload is retained.
  let detached = detachVerifiedAvailability(transfer, store.limits.bytes)
  if detached.error != AvailabilityTransferError.None: return AvailabilityStoreError.InvalidTransfer
  var removed = default(array[MaxAvailabilityEntries, bool])
  var count = store.count
  var retained = store.bytes
  while uint64(count) >= uint64(store.limits.entries) or retained > uint64(
      store.limits.bytes)-bytes:
    let oldest = store.oldestEntry(removed)
    if oldest < 0 or count <= 0 or store.entries[oldest].bytes > retained:
      return AvailabilityStoreError.Conflict
    removed[oldest] = true
    retained -= store.entries[oldest].bytes
    dec count
  var position = -1
  for index in 0..<MaxAvailabilityEntries:
    if removed[index] or not store.entries[index].used:
      position = index
      break
  if position < 0: return AvailabilityStoreError.LimitExceeded
  for index in 0..<MaxAvailabilityEntries:
    if removed[index]: store.entries[index] = default(Entry)
  inc store.next
  store.entries[position] = Entry(used: true, age: store.next, bytes: bytes,
      transfer: detached.value)
  store.bytes = retained+bytes
  store.count = count+1
  AvailabilityStoreError.None

proc find*(store: var AvailabilityStore, request: AvailabilityRequest): AvailabilityStoreResult =
  ## Exact root/shard lookup supplies only the distribution for later bounded audit computation.
  if not store.configured: return AvailabilityStoreResult(
      status: AvailabilityStoreError.Unconfigured)
  if store.next == high(uint64): return AvailabilityStoreResult(
      status: AvailabilityStoreError.Exhausted)
  for index in 0..<MaxAvailabilityEntries:
    if not store.entries[index].used: continue
    let selected = store.entries[index].transfer.request
    if selected.root.bytes == request.root.bytes and uint64(selected.shard) == uint64(request.shard):
      inc store.next
      store.entries[index].age = store.next
      return AvailabilityStoreResult(status: AvailabilityStoreError.None, completed: store.entries[
          index].transfer)
  AvailabilityStoreResult(status: AvailabilityStoreError.Missing)

func configured*(store: AvailabilityStore): bool =
  ## Scalar policy observation remains safe while a worker borrows immutable entries.
  store.configured

proc snapshot*(store: AvailabilityStore): seq[VerifiedAvailabilityTransfer] =
  ## The caller freezes all store aliases through CPU retirement; only module-private Services uses this graph handoff.
  result = @[]
  for entry in store.entries:
    if entry.used: result.add(entry.transfer)
