# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A bounded source-free ledger keeps qualified original judgments and both sides of equivocation. Whole batches reserve every new row before mutation; no full execution state or private key enters gossip storage.
import ./[judgment_receipt, judgment_claim, audits]
import ../codec/[bounded, disputes]

const MaxLocalJudgments* = 32768

type
  JudgmentStoreLimits* = object ## Optional explicit finite row and byte credit governs retained accountable records.
    records*: ElementLimit
    bytes*: ByteLimit
  JudgmentStore* = object ## Host-only mutable rows own fixed detached records, never leased complete-state aliases.
    enabled: bool
    limits: JudgmentStoreLimits
    rows: seq[QualifiedJudgment]
    minimumEpoch: uint64
  JudgmentStoreError* {.pure.} = enum ## No refused batch publishes an accepted prefix.
    Uninitialized, None, Unconfigured, InvalidPolicy, InvalidRecord, InvalidIndex, LimitExceeded, Expired
  JudgmentStoreResult*[T] = object ## Defaults and failures carry only their reason.
    case status: JudgmentStoreError
    of None: completed: T
    else: discard                  # No accepted prefix or fabricated qualified record survives refusal.
func error*[T](outcome: JudgmentStoreResult[T]): JudgmentStoreError =
  ## Select complete success before extracting any insertion or lookup result.
  outcome.status
func value*[T](outcome: JudgmentStoreResult[T]): T {.requires: outcome.status ==
    JudgmentStoreError.None.} =
  ## Only complete batch admission or checked ordinal lookup carries data.
  outcome.completed
func valid*(limits: JudgmentStoreLimits): bool =
  ## A small fixed row ceiling bounds duplicate/conflict planning independently of byte accounting.
  uint64(limits.records) in 1'u64..uint64(MaxLocalJudgments) and
    uint64(limits.bytes) in 1'u64..64'u64*1024*1024
func len*(store: JudgmentStore): int =
  ## Occupancy remains safe during unrelated canonical/private-source leases.
  store.rows.len
func configured*(store: JudgmentStore): bool =
  ## Omission never activates judgment retention.
  store.enabled
proc configure*(store: var JudgmentStore, limits: JudgmentStoreLimits): bool =
  ## Reconfiguration cannot discard live accountable evidence or silently widen local policy.
  if store.enabled or not limits.valid or sizeof(QualifiedJudgment) > 1024: return false
  store.enabled = true
  store.limits = limits
  true
func fitsCount(store: JudgmentStore, count: uint64): bool =
  ## The explicit ledger and at most sixteen new rows bound this calculation.
  count <= uint64(store.limits.records) and
    4096+count*(uint64(sizeof(QualifiedJudgment))+64) <= uint64(store.limits.bytes)
proc expireBefore*(store: var JudgmentStore, minimumEpoch: uint64) =
  ## Release old accountable records and keep the floor even if no rows survived.
  if minimumEpoch <= store.minimumEpoch: return
  store.minimumEpoch = minimumEpoch
  var kept = 0
  for ordinal in 0..<store.rows.len:
    # The original signed epoch applies equally to both sides of a conflict.
    if uint64(uint32(store.rows[ordinal].judgmentRecord.epoch)) >= minimumEpoch:
      if kept != ordinal: store.rows[kept] = move(store.rows[ordinal])
      inc kept
  store.rows.setLen(kept)
proc canAppendClaims*(store: JudgmentStore, claims: SignedJudgmentBatch): bool =
  ## Preflight only: unsupported negative signatures can reserve capacity but cannot insert a qualified record or private source. The single host actor keeps this ledger unchanged through receipt.
  if not store.enabled or not claims.valid or claims.len > 16: return false
  var additions: seq[SignedJudgmentClaim] = @[]
  for ordinal in 0..<claims.len:
    # Reserve exactly the duplicate/conflict identities later used by qualified insertion before any expensive report acquisition or private origin installation.
    let claim = claims.claimAt(ordinal).value
    let incoming = claim.judgmentRecord
    let auditor = claim.claimInfo.auditor.ed25519
    if uint64(uint32(incoming.epoch)) < store.minimumEpoch: return false
    var duplicate = false
    for prior in store.rows:
      let existing = prior.judgmentRecord
      if sameJudgmentKey(incoming, existing, auditor, prior.judgmentAuditor) and
          incoming.valid == existing.valid: duplicate = true
    for prior in additions:
      let existing = prior.judgmentRecord
      if sameJudgmentKey(incoming, existing, auditor, prior.claimInfo.auditor.ed25519) and
          incoming.valid == existing.valid: duplicate = true
    if not duplicate: additions.add(claim)
  store.fitsCount(uint64(store.rows.len+additions.len))
proc append*(store: var JudgmentStore, batch: openArray[QualifiedJudgment]): JudgmentStoreResult[int] =
  ## Same-key/same-validity retries are idempotent; opposite valid claims are both retained. Whole-message capacity is checked before the first insertion.
  if not store.enabled: return JudgmentStoreResult[int](status: JudgmentStoreError.Unconfigured)
  if batch.len > 16: return JudgmentStoreResult[int](status: JudgmentStoreError.LimitExceeded)
  var additions: seq[QualifiedJudgment] = @[]
  for record in batch:
    # At most sixteen records compare against the configured retained rows; invalid late records leave the ledger unchanged.
    if not record.valid: return JudgmentStoreResult[int](status: JudgmentStoreError.InvalidRecord)
    let incoming = record.judgmentRecord
    if uint64(uint32(incoming.epoch)) < store.minimumEpoch:
      return JudgmentStoreResult[int](status: JudgmentStoreError.Expired)
    var duplicate = false
    for prior in store.rows:
      let existing = prior.judgmentRecord
      if sameJudgmentKey(record, prior) and incoming.valid == existing.valid: duplicate = true
    for prior in additions:
      let existing = prior.judgmentRecord
      if sameJudgmentKey(record, prior) and incoming.valid == existing.valid: duplicate = true
    if not duplicate: additions.add(record)
  let count = uint64(store.rows.len+additions.len)
  # Validated fixed rows and explicit row policy prove these additions/products cannot wrap.
  if not store.fitsCount(count):
    return JudgmentStoreResult[int](status: JudgmentStoreError.LimitExceeded)
  for record in additions:
    # No protocol/resource refusal remains after whole-batch reservation.
    store.rows.add(record)
  JudgmentStoreResult[int](status: JudgmentStoreError.None, completed: additions.len)
proc containsReport*(store: JudgmentStore, hash: openArray[byte]): bool =
  ## Keep exact CE136 bytes while any eligible record still names their full report hash.
  if hash.len != 32: return false
  for row in store.rows:
    if hash == array[32, byte](row.judgmentRecord.report): return true
  false
proc judgmentAt*(store: JudgmentStore, ordinal: int): JudgmentStoreResult[QualifiedJudgment] =
  ## Copied fixed records remain valid after unrelated sources retire; no mutable backing sequence escapes.
  if not store.enabled: return JudgmentStoreResult[QualifiedJudgment](
      status: JudgmentStoreError.Unconfigured)
  if ordinal < 0 or ordinal >= store.rows.len:
    return JudgmentStoreResult[QualifiedJudgment](status: JudgmentStoreError.InvalidIndex)
  JudgmentStoreResult[QualifiedJudgment](status: JudgmentStoreError.None, completed: store.rows[ordinal])
proc conflicted*(store: JudgmentStore, ordinal: int): bool =
  ## Accountable conflict means two independently qualified opposite signed claims for the exact same original key; it does not choose report truth.
  if ordinal < 0 or ordinal >= store.rows.len: return false
  let selected = store.rows[ordinal].judgmentRecord
  for record in store.rows:
    let other = record.judgmentRecord
    if sameJudgmentKey(store.rows[ordinal], record) and selected.valid != other.valid: return true
  false
proc clear*(store: var JudgmentStore) =
  ## Explicit host lifecycle releases bounded detached evidence without touching any private source or key owner.
  store.rows = @[]
  store.enabled = false
  store.limits = default(JudgmentStoreLimits)
  store.minimumEpoch = 0
