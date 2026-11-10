# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source-free bounded pending guarantees retain exact canonical bytes until GP credential expiry or explicit host teardown.
## This is neither block admission nor the long-lived shard retention promised by an assurance.

import std/assertions
import ./services
import ../jamnp-s/work_distribution
import ../codec/bounded
import ../codec/state/safrole

const MaxPendingGuarantees* = 64 ## Fixed host storage does not grow with peer announcements.
type
  PendingGuarantee = object ## Fixed provenance and independent wire bytes contain no canonical map or signer alias.
    used: bool
    info: WorkDistributionInfo
    wire: seq[byte]
  WorkGuaranteePool* = object ## Capacity and byte budgets are selected explicitly before the first accepted report.
    entries: array[MaxPendingGuarantees, PendingGuarantee]
    limit: int
    budget: uint64
    count, bytes: int

func len*(pool: WorkGuaranteePool): int =
  ## Scalar occupancy is safe through any foreign canonical lease.
  pool.count

func byteLength*(pool: WorkGuaranteePool): int =
  ## Count exact retained canonical payload bytes, independently from framed report-cache storage.
  pool.bytes

proc configure*(pool: var WorkGuaranteePool, entries: range[1..MaxPendingGuarantees],
    bytes: ByteLimit): bool =
  ## Omission/default leaves no capacity; a configured pool cannot silently replace live retention policy.
  if pool.limit != 0 or uint64(bytes) == 0 or uint64(bytes) > 32'u64*1024*1024: return false
  pool.limit = entries
  pool.budget = uint64(bytes)
  true

proc clear*(pool: var WorkGuaranteePool) =
  ## These owners contain no worker-shared graph, so host shutdown need not borrow canonical state to retire them.
  pool = default(WorkGuaranteePool)

proc expire*(pool: var WorkGuaranteePool, now: StateTime) =
  ## GP current/previous rotation credential expiry is fixed by the chain geometry used during verification.
  for index in 0..<MaxPendingGuarantees:
    if pool.entries[index].used and uint32(pool.entries[index].info.lastSlot) < uint32(now):
      pool.bytes -= pool.entries[index].wire.len
      dec pool.count
      pool.entries[index] = default(PendingGuarantee)

func position(pool: WorkGuaranteePool, info: WorkDistributionInfo): int =
  ## A new encoded timeslot is a distinct guarantee even when its report hash is unchanged.
  for index in 0..<MaxPendingGuarantees:
    if pool.entries[index].used:
      let old = pool.entries[index].info
      if old.reportHash == info.reportHash and uint32(old.slot) == uint32(info.slot): return index
  -1

func canRemember*(pool: WorkGuaranteePool, info: WorkDistributionInfo): bool =
  ## Bound persistent bytes/rows before requesting another detached payload copy.
  if pool.limit == 0 or info.wireBytes <= 0: return false
  let found = pool.position(info)
  let prior = if found >= 0: pool.entries[found].wire.len else: 0
  if found < 0 and pool.count >= pool.limit: return false
  let used = uint64(pool.bytes-prior)
  used <= pool.budget and uint64(info.wireBytes) <= pool.budget-used

proc remember*(pool: var WorkGuaranteePool, completed: WorkDistributionCompletion): bool =
  ## Only a genuine detached Services completion may populate the pool; capacity refusal never acknowledges unretained data.
  if completed.kind != WorkDistributionCompletionKind.Completed: return false
  let info = completed.distributionInfo
  var found = pool.position(info)
  if found >= 0:
    let old = pool.entries[found].info
    let sameSource = array[32, byte](old.root) == array[32, byte](info.root)
    if sameSource and old.credentials >= info.credentials: return true
  if not pool.canRemember(info): return false
  if found < 0:
    for index in 0..<MaxPendingGuarantees:
      if not pool.entries[index].used:
        found = index
        break
  if found < 0: return false
  let wire = completed.distributionPayload
  if wire.len != info.wireBytes: return false
  if pool.entries[found].used:
    pool.bytes -= pool.entries[found].wire.len
  else:
    inc pool.count
  pool.entries[found] = PendingGuarantee(used: true, info: info, wire: wire)
  pool.bytes += wire.len
  true

proc payloadAt*(pool: WorkGuaranteePool, ordinal: int): seq[byte] {.requires: ordinal >= 0 and
    ordinal < pool.count.} =
  ## Return independent candidate bytes; a later block/assurer worker must perform its own fresh source-bound admission.
  var selected = 0
  for index in 0..<MaxPendingGuarantees:
    if pool.entries[index].used:
      if selected == ordinal:
        result = newSeq[byte](pool.entries[index].wire.len)
        for octet in 0..<result.len: result[octet] = pool.entries[index].wire[octet]
        return
      inc selected
  assert false # The required occupancy invariant makes this branch unreachable.
