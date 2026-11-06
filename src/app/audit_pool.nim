# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bounded source-free pool remembers whole verified audit declarations; duplicate records consume no new intent capacity and late capacity refusal inserts nothing.
import ../jamnp-s/[audit_receipt, audit_validation, audits, audit_context]
import ../codec/bounded

type AuditIntentPool* = object ## Mutable ownership stays inside the stable host controller; immutable checked children contain no canonical graph.
  capacity: int
  maximum, occupied: uint64
  records: seq[CheckedAuditAnnouncement]
func len*(pool: AuditIntentPool): int =
  ## Count original declarations independently of their at-most-ten selected available cores.
  pool.records.len
func occupiedBytes*(pool: AuditIntentPool): uint64 =
  ## Conservative retained-context charges include fixed record and sequence overhead.
  pool.occupied
proc configure*(pool: var AuditIntentPool, entries: range[1..256], bytes: ByteLimit): bool =
  ## Omission leaves no capacity and an existing incarnation cannot be reconfigured over retained obligations.
  if pool.capacity != 0 or uint64(bytes) == 0 or uint64(bytes) > 256'u64*1024*1024: return false
  pool.capacity = entries
  pool.maximum = uint64(bytes)
  true
proc same(left, right: CheckedAuditAnnouncement): bool =
  ## The original header/validator/intent/core tuple identifies a declaration independently of transport, proof randomness or epoch routing.
  let a = left.announcementRecord.value
  let b = right.announcementRecord.value
  array[32, byte](a.header) == array[32, byte](b.header) and uint16(a.validator) == uint16(
      b.validator) and
    a.intent == b.intent and (a.intent == AuditIntent.Initial or uint16(a.core) == uint16(b.core))
proc contains(pool: AuditIntentPool, record: CheckedAuditAnnouncement): bool =
  ## Bounded linear scans preserve original declarations without a caller-selected hash or mutable index.
  for existing in pool.records:
    if same(existing, record): return true
  false
proc repeated(batch: CheckedAuditBatch, ordinal: int): bool =
  ## Same-message duplicates must be charged only once during whole-batch preflight and insertion.
  let record = batch.announcementAt(ordinal).value
  for previous in 0..<ordinal:
    if same(batch.announcementAt(previous).value, record): return true
  false
proc remember*(pool: var AuditIntentPool, batch: CheckedAuditBatch): bool =
  ## Validate all entry/byte additions before mutating storage; no accepted prefix survives a late refusal.
  if pool.capacity == 0 or not batch.valid: return false
  var additions = 0
  var bytes = 0'u64
  for ordinal in 0..<batch.len:
    let record = batch.announcementAt(ordinal).value
    if pool.contains(record) or batch.repeated(ordinal): continue # Retain an existing declaration exactly once.
    let charge = record.announcementContext.value.contextInfo.value.retainedBytes+1024
    if additions >= pool.capacity-pool.records.len or charge > pool.maximum-pool.occupied-bytes:
      return false
    inc additions
    bytes += charge
  for ordinal in 0..<batch.len:
    let record = batch.announcementAt(ordinal).value
    if not pool.contains(record): pool.records.add(
        record) # Whole preflight proved capacity; existing and same-batch duplicates now share one stored record.
  pool.occupied += bytes
  true
proc announcementAt*(pool: AuditIntentPool, ordinal: int): CheckedAuditAnnouncement {.requires: ordinal >=
    0 and ordinal < pool.records.len.} =
  ## Return only an immutable already authenticated declaration, never private mutable backing storage.
  pool.records[ordinal]
proc clear*(pool: var AuditIntentPool) =
  ## Explicit controller shutdown releases every source-free context and resets the complete capacity incarnation.
  pool.records = @[]
  pool.capacity = 0
  pool.maximum = 0
  pool.occupied = 0
