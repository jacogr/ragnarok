# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Resolve every complete-inventory service's current code identity, content and historical availability under independent bounded work policies.
import ../codec/bounded as codec_bounded
import ../codec/state_accounts as codec_state_accounts
import ../codec/state_layout as codec_state_layout
import ../codec/state_requests as codec_state_requests
import ../crypto/primitives as crypto_primitives
import ./inventory as state_inventory
import ./manifest as state_manifest
import ./store as state_store
import ./preimage_history as state_preimage_history
type
  CodeAvailabilityLimits* = object ## Full row/child visits, retained descriptors and selected content copies/hashes have separate ceilings.
    services*, visits*: ElementLimit
    descriptors*, perCode*, totalCodeBytes*: ByteLimit
  ServiceCodeState* {.pure.} = enum ## Stored content outside its historical interval differs from a completely absent code preimage.
    Absent, Unavailable, Available
  ServiceCodeInfo* = object ## Copied fixed observations remain bound to an explicitly selected slot and the account's own current code identity.
    service*: ServiceIndex
    hash*: CodeHash
    state*: ServiceCodeState
    bytes*: uint64
  CodeAvailabilityInfo* = object ## Whole-source coverage reports observations, never a new account or chain validity rule.
    services*, present*, available*: int
    bytes*, descriptors*: uint64
    slot*: RequestSlot
  CodeRow = object ## A physical key remains private and usable only for its original bounded available content.
    info: ServiceCodeInfo
    key: StateKey
  CodeData = ref object ## The exact complete inventory and copied fixed rows form one immutable acyclic owner.
    source: StateInventory
    rows: seq[CodeRow]
    info: CodeAvailabilityInfo
  StateCodeAvailability* = object ## No caller can substitute code hashes, histories or independently recaptured inventories.
    data: nil CodeData
  CodeAvailabilityError* {.pure.} = enum ## Default/source/quota, association, content and backend refusals grant no successful table prefix.
    Uninitialized, None, InvalidSource, LimitExceeded, MissingRequest, HashMismatch,
      BackendFailure, InvalidIndex, NoService, Unavailable
  CodeAvailabilityResult*[T] = object ## Only whole successful audits or guarded owner-bound reads expose values.
    case status: CodeAvailabilityError
    of None: completed: T
    of MissingRequest, HashMismatch, BackendFailure: service: ServiceIndex
    else: discard # Refused audit and read alternatives carry no default code bytes.
  CodeSelection = object ## Internal fixed selection borrows no payload and distinguishes absence from missing history.
    present, linked: bool
    fact: InventoryPreimageFact
    history: RequestHistory
func error*[T](outcome: CodeAvailabilityResult[T]): CodeAvailabilityError =
  ## Observe the immutable selected alternative without granting its backing owner.
  outcome.status
func value*[T](outcome: CodeAvailabilityResult[T]): T {.inline, requires: outcome.status ==
    CodeAvailabilityError.None.} =
  ## Only complete successful results authorize table, info or detached code extraction.
  outcome.completed
func failedService*[T](outcome: CodeAvailabilityResult[T]): ServiceIndex {.inline,
    requires: outcome.status in {CodeAvailabilityError.MissingRequest,
    CodeAvailabilityError.HashMismatch, CodeAvailabilityError.BackendFailure}.} =
  ## Only a genuine selected association or content failure identifies an offending service.
  outcome.service
proc selectCode(source: StateInventory, ordinal: InventoryServiceIndex): CodeSelection =
  ## Callers first admit complete worst-case visits; select metadata's own hash and the actual blob-length request only.
  result = default(CodeSelection)
  let row = source.inventoryServiceAt(ordinal).value
  for j in 0..<row.preimages:
    let fact = source.inventoryPreimageAt(ordinal, InventoryPreimageIndex(uint64(j))).value
    if array[32, byte](fact.hash) == array[32, byte](row.metadata.codeHash):
      result.present = true
      result.fact = fact
      break # Complete capture guarantees unique physical preimage identities.
  if result.present:
    for j in 0..<row.requests:
      let request = source.inventoryRequestAt(ordinal, InventoryRequestIndex(uint64(j))).value
      if array[32, byte](request.hash) == array[32, byte](row.metadata.codeHash) and uint64(uint32(
          request.length)) == result.fact.bytes:
        result.linked = true
        result.history = request.history
        break # Exact hash/actual length identity cannot be replaced by another request.
proc auditCodeAvailability*(source: StateInventory, slot: RequestSlot,
    limits: CodeAvailabilityLimits): CodeAvailabilityResult[StateCodeAvailability] =
  ## Preflight the entire complete inventory before allocating descriptors, copying code or invoking content hashes.
  template fail(reason: CodeAvailabilityError) =
    return CodeAvailabilityResult[StateCodeAvailability](status: reason)
  let info = source.inventoryInfo
  if info.error != StateInventoryError.None: fail(CodeAvailabilityError.InvalidSource)
  let count = info.value.services
  let budget = min(uint64(limits.descriptors), uint64(high(int)))
  if uint64(count) > uint64(limits.services) or uint64(count) > budget div uint64(sizeof(CodeRow)):
    fail(CodeAvailabilityError.LimitExceeded) # Division proves native descriptor multiplication before allocation.
  var visits = uint64(limits.visits)
  for i in 0..<count:
    let row = source.inventoryServiceAt(InventoryServiceIndex(uint64(i))).value
    template charge(amount: int) =
      block:
        let extent = uint64(amount)
        if extent > visits div 2: fail(CodeAvailabilityError.LimitExceeded)
        visits -= extent*2 # Two fixed-selection passes fit without addition or multiplication overflow.
    charge(row.preimages)
    charge(row.requests)
  var bytes = uint64(limits.totalCodeBytes)
  for i in 0..<count:
    let ordinal = InventoryServiceIndex(uint64(i))
    let selected = selectCode(source, ordinal)
    if selected.present:
      if not selected.linked:
        return CodeAvailabilityResult[StateCodeAvailability](
            status: CodeAvailabilityError.MissingRequest, service: source.inventoryServiceAt(
            ordinal).value.service)
      if selected.fact.bytes > uint64(limits.perCode) or selected.fact.bytes > bytes:
        fail(CodeAvailabilityError.LimitExceeded) # Admit every selected payload before the first content copy/hash.
      bytes -= selected.fact.bytes
  var rows = newSeq[CodeRow](count)
  let snapshot = source.inventorySource.value.manifestSource.value
  var report = CodeAvailabilityInfo(services: count, descriptors: uint64(count)*uint64(sizeof(
      CodeRow)), bytes: uint64(limits.totalCodeBytes)-bytes, slot: slot)
  for i in 0..<count:
    let ordinal = InventoryServiceIndex(uint64(i))
    let row = source.inventoryServiceAt(ordinal).value
    let selected = selectCode(source, ordinal)
    rows[i].info = ServiceCodeInfo(service: row.service, hash: row.metadata.codeHash,
        state: ServiceCodeState.Absent)
    if selected.present:
      let content = snapshot.lookup(selected.fact.key).value
      let hashed = blake2b256(content.bytes)
      if hashed.error != CryptoError.None:
        return CodeAvailabilityResult[StateCodeAvailability](
            status: CodeAvailabilityError.BackendFailure, service: row.service)
      if array[32, byte](hashed.value) != array[32, byte](row.metadata.codeHash):
        return CodeAvailabilityResult[StateCodeAvailability](
            status: CodeAvailabilityError.HashMismatch, service: row.service)
      rows[i].key = selected.fact.key
      rows[i].info.bytes = selected.fact.bytes
      rows[i].info.state = ServiceCodeState.Unavailable
      inc report.present
      if requestAvailableAt(selected.history, slot):
        rows[i].info.state = ServiceCodeState.Available
        inc report.available # Requested and out-of-interval blobs remain observed unavailable.
  CodeAvailabilityResult[StateCodeAvailability](status: CodeAvailabilityError.None,
    completed: StateCodeAvailability(data: CodeData(source: source, rows: rows, info: report)))
proc codeAvailabilityInfo*(table: StateCodeAvailability): CodeAvailabilityResult[
    CodeAvailabilityInfo] =
  ## Copy whole-source observations without exposing mutable rows or storage.
  let data = table.data
  if data == nil: return CodeAvailabilityResult[CodeAvailabilityInfo](
      status: CodeAvailabilityError.Uninitialized)
  CodeAvailabilityResult[CodeAvailabilityInfo](status: CodeAvailabilityError.None,
      completed: data.info)
proc codeAvailabilityInventory*(table: StateCodeAvailability): CodeAvailabilityResult[
    StateInventory] =
  ## Retain the exact original complete compact owner for checked predicate joins.
  let data = table.data
  if data == nil: return CodeAvailabilityResult[StateInventory](
      status: CodeAvailabilityError.Uninitialized)
  CodeAvailabilityResult[StateInventory](status: CodeAvailabilityError.None, completed: data.source)
proc serviceCodeAt*(table: StateCodeAvailability, index: int): CodeAvailabilityResult[
    ServiceCodeInfo] =
  ## Check signed native indices before reading one copied fixed row.
  let data = table.data
  if data == nil: return CodeAvailabilityResult[ServiceCodeInfo](
      status: CodeAvailabilityError.Uninitialized)
  if index < 0 or index >= data.rows.len: return CodeAvailabilityResult[ServiceCodeInfo](
      status: CodeAvailabilityError.InvalidIndex)
  CodeAvailabilityResult[ServiceCodeInfo](status: CodeAvailabilityError.None, completed: data.rows[index].info)
proc findServiceCode*(table: StateCodeAvailability, service: ServiceIndex): CodeAvailabilityResult[int] =
  ## Search only already admitted fixed rows; absent account identity differs from an account with no stored code.
  let data = table.data
  if data == nil: return CodeAvailabilityResult[int](status: CodeAvailabilityError.Uninitialized)
  for i in 0..<data.rows.len:
    if data.rows[i].info.service == service: return CodeAvailabilityResult[int](
        status: CodeAvailabilityError.None, completed: i)
  CodeAvailabilityResult[int](status: CodeAvailabilityError.NoService)
proc copyServiceCode*(table: StateCodeAvailability, index: int,
    limit: ByteLimit): CodeAvailabilityResult[seq[byte]] =
  ## Copy available code only after owner/index/state/extent checks; present-empty bytes remain distinct from absence.
  let observed = table.serviceCodeAt(index)
  if observed.error != CodeAvailabilityError.None: return CodeAvailabilityResult[seq[byte]](
      status: observed.error)
  if observed.value.state != ServiceCodeState.Available: return CodeAvailabilityResult[seq[byte]](
      status: CodeAvailabilityError.Unavailable)
  if observed.value.bytes > uint64(limit): return CodeAvailabilityResult[seq[byte]](
      status: CodeAvailabilityError.LimitExceeded)
  let data = table.data
  if data == nil: return CodeAvailabilityResult[seq[byte]](
      status: CodeAvailabilityError.Uninitialized)
  let snapshot = data.source.inventorySource.value.manifestSource.value
  CodeAvailabilityResult[seq[byte]](status: CodeAvailabilityError.None, completed: snapshot.lookup(
      data.rows[index].key).value.bytes)
