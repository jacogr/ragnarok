# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 preimagesareordered/fnprovidable/fnprovide: prior admission and atomic post-accumulation integration.
## Exposes canonical outstanding-request queries, immutable admission/statistics certificates and atomic publication.
## Phase/slot binding is caller-owned; query/admission share exact account/history validation.

import ../codec/[bounded, composite, owned, header, state_layout, state_trie, state_accounts,
  state_service_values, state_requests]
import ../crypto/primitives
import ./store

type
  ProvisionIndex* = distinct uint64 ## Statistics traversal addresses service groups rather than individual supplied blobs.
  ProvisionCount* = distinct uint64 ## Actual provided counters are not byte ceilings, slots or gas amounts.
  ProvisionBytes* = distinct uint64 ## Actual total provided octets remain distinct from counts and caller byte ceilings.
  PreimageProvision* = object ## Per-service block statistics contribution counts admitted extrinsic data, even if later no longer needed.
    service*: ServiceIndex
    count*: ProvisionCount
    bytes*: ProvisionBytes
  PreimageAdmissionInfo* = object ## Selected complete admission facts contain no detached blob spans.
    items*, services*: int
    bytes*: ProvisionBytes
  PreimageTransitionError* {.pure.} = enum ## Refusal never exposes partially admitted input, proposed writes or a candidate state root.
    Uninitialized, None, InvalidInput, InvalidState, NotOrderedUnique, NotRequested,
    MalformedState, LimitExceeded, BackendFailure, InvalidIndex
  ## Fixed private rows cache only identities proved from the retained input; no caller buffer is trusted later.
  PreimageRow = object
    service: ServiceIndex
    hash: ServicePreimageHash
    request: StateKey
    length: int
  ## Private acyclic owner binds exact input/prior state and sorted per-service statistics.
  PreimageData = ref object
    prior: StateStoreSnapshot
    source: OwnedFrame
    rows: seq[PreimageRow]
    provisions: seq[PreimageProvision]
    bytes: ProvisionBytes
  AdmittedPreimages* = object ## Read-only certificate cannot be constructed from substituted source coordinates or changed state.
    data: nil PreimageData
  PreparedPreimageValues* = object ## Canonical value-set identities are prepared independently from posterior state, without granting extrinsic admission.
    data: nil PreimageData
  PreimageTransitionResult*[T] = object ## Only selected success carries owners, fixed observations or an atomically committed map.
    case status: PreimageTransitionError
    of None:
      completed: T # No default payload may be read after failure.
    else:
      discard      # Keep failures and incomplete progress value-free.

func error*[T](outcome: PreimageTransitionResult[T]): PreimageTransitionError =
  ## Read a reason without granting result mutation or retagging.
  outcome.status
func value*[T](outcome: PreimageTransitionResult[T]): T {.inline,
    requires: outcome.status == PreimageTransitionError.None.} =
  ## Extract selected success under supported compiler/runtime contracts in optimized builds too.
  outcome.completed

## Map complete-store failures without changing backend/resource refusals into protocol invalidity.
func storeReason(reason: StateStoreError): PreimageTransitionError =
  case reason
  of StateStoreError.BackendFailure: PreimageTransitionError.BackendFailure # Never fabricate a state root.
  of StateStoreError.LimitExceeded, StateStoreError.LengthOverflow: PreimageTransitionError.LimitExceeded # Preserve local policy/native extent refusal.
  else: PreimageTransitionError.InvalidState # Default owners or conflicting writes cannot publish state.

## Require an existing structurally valid account and an exact canonical zero-slot request history.
## Missing accounts/requests and nonempty histories are ordinary false; malformed present values are refusals.
proc outstanding(state: StateStoreSnapshot, service: ServiceIndex,
    request: StateKey): PreimageTransitionResult[bool] =
  let account = state.lookup(chapterServiceKey(StateChapter(255), service))
  if account.error == StateStoreError.MissingKey:
    return PreimageTransitionResult[bool](status: PreimageTransitionError.None,
        completed: false) # Orphan requests do not create accounts.
  if account.error != StateStoreError.None:
    return PreimageTransitionResult[bool](status: storeReason(account.error)) # Default maps cannot imply absence.
  if account.value.byteLength != ServiceMetadataBytes:
    return PreimageTransitionResult[bool](status: PreimageTransitionError.MalformedState) # Prove the fixed extent before copying.
  if decodeServiceMetadata(account.value.bytes, ByteLimit(ServiceMetadataBytes)).error !=
      ServiceMetadataError.None:
    return PreimageTransitionResult[bool](status: PreimageTransitionError.MalformedState) # Unsupported account versions are not repaired.
  let found = state.lookup(request)
  if found.error == StateStoreError.MissingKey:
    return PreimageTransitionResult[bool](status: PreimageTransitionError.None,
        completed: false) # Missing is not an empty outstanding history.
  if found.error != StateStoreError.None:
    return PreimageTransitionResult[bool](status: storeReason(found.error)) # No fabricated requested state.
  if found.value.byteLength > 13:
    return PreimageTransitionResult[bool](status: PreimageTransitionError.MalformedState) # Bound copies to the protocol maximum.
  let decoded = decodeRequestHistory(found.value.bytes,
    RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13)))
  if decoded.error != RequestError.None:
    return PreimageTransitionResult[bool](status: PreimageTransitionError.MalformedState) # Truncated/noncanonical histories are not outstanding.
  if decoded.value.consumed != found.value.byteLength:
    return PreimageTransitionResult[bool](status: PreimageTransitionError.MalformedState) # Require the entire stored value, not a prefix.
  PreimageTransitionResult[bool](status: PreimageTransitionError.None,
    completed: decoded.value.history.state == RequestState.Requested)

proc preimageRequested*(state: StateStoreSnapshot, service: ServiceIndex,
    hash: ServicePreimageHash, length: RequestLength): PreimageTransitionResult[bool] =
  ## Query an exact canonical outstanding request without accepting a caller-selected namespace key.
  ## Missing accounts/requests or nonempty histories are false; malformed maps/backend failure are typed refusals.
  let key = serviceRequestKey(service, hash, length, ByteLimit(32))
  if key.error != RequestError.None:
    # Namespace derivation failure cannot fabricate a requested/unrequested verdict.
    return PreimageTransitionResult[bool](status: PreimageTransitionError.BackendFailure)
  outstanding(state, service, key.value)

## Compare raw byte sequences lexicographically; wire lengths and hash digests do not order equal-service blobs.
func compareBlob(a, b: openArray[byte]): int =
  for i in 0..<min(a.len, b.len):
    if a[i] < b[i]: return -1 # First unequal raw octet determines ordering.
    if a[i] > b[i]: return 1 # Greater raw octets must follow smaller ones.
  cmp(a.len, b.len) # A proper prefix sorts before its extension; equal lengths here imply duplicate data.

## Admit exact source ordering and prior-state solicitation after complete work/copy preflight.
## Prepare bounded canonical identities; only explicit extrinsic admission additionally requires prior solicitation.
proc preparePreimages(prior: StateStoreSnapshot, source: OwnedFrame,
    limits: PreimageLimits, requireRequested: bool): PreimageTransitionResult[PreimageData] =
  ## Refuse atomically; no earlier row or provision counter escapes a later invalid item.
  template fail(reason: PreimageTransitionError) =
    return PreimageTransitionResult[PreimageData](status: reason)
  let meta = source.ownedInfo
  if meta.error != OwnershipError.None: fail(PreimageTransitionError.InvalidInput) # Defaults have no validated schema.
  if meta.value.kind != OwnedKind.Preimages: fail(
      PreimageTransitionError.InvalidInput) # Other owned frames cannot supply this extrinsic.
  let count = meta.value.blobCount
  if uint64(count) > uint64(limits.items) or count > high(int) div sizeof(PreimageRow) or
      count > high(int) div sizeof(PreimageProvision) or count > high(int) div (2*sizeof(StateWrite)):
    fail(PreimageTransitionError.LimitExceeded) # Prove row/statistics/write descriptor bounds before allocation.
  if requireRequested:
    # Prior-state provenance belongs only to extrinsic admission, never to a prepared value-set certificate.
    let check = prior.lookup(chapterKey(StateChapter(0)))
    if check.error != StateStoreError.None and check.error != StateStoreError.MissingKey:
      fail(PreimageTransitionError.InvalidState) # Even an empty extrinsic requires an initialized complete-map owner.
  var total = 0'u64
  # Inspect all actual payload extents before copying the first blob or hashing any input.
  for i in 0..<count:
    let size = uint64(source.ownedBlobLength(i).value)
    if size > uint64(high(uint32)) or size > uint64(limits.perBlob) or size > uint64(
        limits.totalBlobBytes)-total:
      fail(PreimageTransitionError.LimitExceeded) # Request lengths are E4; subtract before aggregate addition under wrapping arithmetic.
    total += size
  let data = PreimageData(prior: prior, source: source, rows: newSeq[PreimageRow](count),
    provisions: @[], bytes: ProvisionBytes(total))
  var previous: seq[byte] = @[]
  var previousService = 0'u32
  # Preserve input order; reject rather than sort or deduplicate hostile extrinsics.
  for i in 0..<count:
    let service = source.ownedService(i).value
    let size = source.ownedBlobLength(i).value
    var blob = newSeq[byte](size)
    discard source.copyOwnedBlob(i, blob).value
    if i != 0 and (uint32(service) < previousService or
        (uint32(service) == previousService and compareBlob(previous, blob) >= 0)):
      fail(PreimageTransitionError.NotOrderedUnique) # Numeric service, then strictly increasing raw blob, is the only ordering.
    let digest = blake2b256(blob)
    if digest.error != CryptoError.None: fail(PreimageTransitionError.BackendFailure) # A failed hash is never an unsolicited preimage verdict.
    let hash = ServicePreimageHash(array[32, byte](digest.value))
    let key = serviceRequestKey(service, hash, RequestLength(uint32(size)), ByteLimit(32))
    if key.error != RequestError.None: fail(PreimageTransitionError.BackendFailure) # Namespace failure cannot create an outstanding request.
    if requireRequested:
      # Extrinsic admission requires prior solicitation; retained accumulation values recheck only at application.
      let requested = outstanding(prior, service, key.value)
      if requested.error != PreimageTransitionError.None: fail(
          requested.error) # Preserve malformed/default state distinction.
      if not requested.value: fail(PreimageTransitionError.NotRequested) # Admission always consults prior state, never an altered working map.
    data.rows[i] = PreimageRow(service: service, hash: hash, request: key.value, length: size)
    if i == 0 or uint32(service) != previousService:
      data.provisions.add(PreimageProvision(service: service, count: ProvisionCount(1),
        bytes: ProvisionBytes(uint64(size)))) # Sorted service boundaries begin a fresh contribution.
    else:
      let last = data.provisions.len-1
      data.provisions[last].count = ProvisionCount(uint64(data.provisions[last].count)+1)
      data.provisions[last].bytes = ProvisionBytes(uint64(data.provisions[last].bytes)+uint64(
          size)) # Each subtotal is bounded by the proved overall count/bytes.
    previousService = uint32(service)
    previous = move(blob)
  PreimageTransitionResult[PreimageData](status: PreimageTransitionError.None,
    completed: data)


proc admitPreimages*(prior: StateStoreSnapshot, source: OwnedFrame,
    limits: PreimageLimits): PreimageTransitionResult[AdmittedPreimages] =
  ## Admit only an ordered, unique and prior-requested extrinsic; relaxed preparation never exposes this certificate.
  let prepared = preparePreimages(prior, source, limits, true)
  if prepared.error != PreimageTransitionError.None:
    return PreimageTransitionResult[AdmittedPreimages](status: prepared.error) # No unadmitted owner escapes.
  PreimageTransitionResult[AdmittedPreimages](status: PreimageTransitionError.None,
    completed: AdmittedPreimages(data: prepared.value))

proc preimageInfo*(plan: AdmittedPreimages): PreimageTransitionResult[PreimageAdmissionInfo] =
  ## Copy admission cardinalities without exposing row storage or source offsets.
  let data = plan.data
  if data == nil: return PreimageTransitionResult[PreimageAdmissionInfo](
      status: PreimageTransitionError.Uninitialized) # Default certificates have no complete counts.
  PreimageTransitionResult[PreimageAdmissionInfo](status: PreimageTransitionError.None,
    completed: PreimageAdmissionInfo(items: data.rows.len, services: data.provisions.len,
        bytes: data.bytes))

proc preimagePrior*(plan: AdmittedPreimages): PreimageTransitionResult[StateStoreSnapshot] =
  ## Retain the exact immutable prior map that authorized these submissions.
  let data = plan.data
  if data == nil: return PreimageTransitionResult[StateStoreSnapshot](
      status: PreimageTransitionError.Uninitialized) # No substitute empty prior state.
  PreimageTransitionResult[StateStoreSnapshot](status: PreimageTransitionError.None,
      completed: data.prior)

proc preimageSource*(plan: AdmittedPreimages): PreimageTransitionResult[OwnedFrame] =
  ## Retain the original owned extrinsic; its existing bounded blob APIs preserve source relationships.
  let data = plan.data
  if data == nil: return PreimageTransitionResult[OwnedFrame](
      status: PreimageTransitionError.Uninitialized) # No default successful input.
  PreimageTransitionResult[OwnedFrame](status: PreimageTransitionError.None, completed: data.source)

proc provisionAt*(plan: AdmittedPreimages, index: ProvisionIndex): PreimageTransitionResult[
    PreimageProvision] =
  ## Extract a fixed per-service provision contribution; full C(13) assembly remains a separate pipeline step.
  let data = plan.data
  if data == nil: return PreimageTransitionResult[PreimageProvision](
      status: PreimageTransitionError.Uninitialized) # No fabricated zero contribution.
  if uint64(index) >= uint64(data.provisions.len): return PreimageTransitionResult[
      PreimageProvision](status: PreimageTransitionError.InvalidIndex) # Prove ordinal before narrowing.
  PreimageTransitionResult[PreimageProvision](status: PreimageTransitionError.None,
    completed: data.provisions[int(uint64(index))])

## Recheck post-accumulation solicitation, prepare complete private writes, then publish in one atomic batch.
## The caller supplies the actual post-accumulation store and authenticated candidate slot; neither is fabricated here.
proc integratePrepared(state: var StateStore, current: StateStoreSnapshot, data: PreimageData,
    slot: HeaderSlot): PreimageTransitionResult[StateStoreSnapshot] =
  ## No mutation occurs before the final complete-map apply succeeds.
  template fail(reason: PreimageTransitionError) =
    return PreimageTransitionResult[StateStoreSnapshot](status: reason)
  var writes: seq[StateWrite] = @[]
  # Use cached owner-bound identities; each target request must still be outstanding after accumulation.
  for i, row in data.rows:
    let needed = outstanding(current, row.service, row.request)
    if needed.error != PreimageTransitionError.None: fail(
        needed.error) # Malformed post-state refuses the whole batch.
    if not needed.value: continue # Deleted services, cancelled requests and now-nonempty histories are ignored.
    var blob = newSeq[byte](row.length)
    discard data.source.copyOwnedBlob(i, blob).value
    let history = serviceRequestEntry(row.service, row.hash, RequestLength(uint32(row.length)),
      availableHistory(RequestSlot(uint32(slot))), RequestEntryConfig(keyBytes: ByteLimit(32),
        history: RequestHistoryConfig(items: ElementLimit(3), maxBytes: ByteLimit(13))))
    if history.error != RequestError.None: fail(PreimageTransitionError.BackendFailure) # Namespace failure leaves the original map untouched.
    let value = servicePreimageEntry(row.service, row.hash, blob,
      ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: ByteLimit(uint64(row.length))))
    if value.error != ServiceValueError.None: fail(
        PreimageTransitionError.BackendFailure) # No partial history publication after a later key refusal.
    writes.add(StateWrite(key: history.value.key, kind: StateWriteKind.Put,
        value: history.value.value))
    writes.add(StateWrite(key: value.value.key, kind: StateWriteKind.Put, value: value.value.value))
  let published = state.apply(writes)
  if published.error != StateStoreError.None: fail(storeReason(
      published.error)) # Store preserves all-or-neither writes/root publication.
  PreimageTransitionResult[StateStoreSnapshot](status: PreimageTransitionError.None,
      completed: published.value)


proc integratePreimages*(state: var StateStore, plan: AdmittedPreimages,
    slot: HeaderSlot): PreimageTransitionResult[StateStoreSnapshot] =
  ## Atomically fulfill the admitted extrinsic against one retained post-accumulation map, preserving prior admission semantics.
  let data = plan.data
  if data == nil:
    return PreimageTransitionResult[StateStoreSnapshot](
        status: PreimageTransitionError.Uninitialized) # Default admission grants no writes.
  let current = state.snapshot
  if current.error != StateStoreError.None:
    return PreimageTransitionResult[StateStoreSnapshot](status: storeReason(
        current.error)) # Even empty application needs a complete map.
  integratePrepared(state, current.value, data, slot)

proc prepareProvidedPreimages*(source: OwnedFrame, limits: PreimageLimits):
    PreimageTransitionResult[PreparedPreimageValues] =
  ## Capture canonical value-set identities once, without claiming prior extrinsic solicitation or producing admission statistics.
  let prepared = preparePreimages(default(StateStoreSnapshot), source, limits, false)
  if prepared.error != PreimageTransitionError.None:
    return PreimageTransitionResult[PreparedPreimageValues](
        status: prepared.error) # All extents/order/hash identities precede application.
  PreimageTransitionResult[PreparedPreimageValues](status: PreimageTransitionError.None,
    completed: PreparedPreimageValues(data: prepared.value))

proc integrateProvidedPreimages*(state: var StateStore, plan: PreparedPreimageValues,
    slot: HeaderSlot): PreimageTransitionResult[StateStoreSnapshot] =
  ## Apply one immutable service/blob set through fnprovide, rechecking posterior requests without rehashing captured values.
  ## This pure boundary never produces an AdmittedPreimages certificate or C(13) contribution.
  let data = plan.data
  if data == nil:
    return PreimageTransitionResult[StateStoreSnapshot](
        status: PreimageTransitionError.Uninitialized) # Default preparation grants no writes.
  let current = state.snapshot
  if current.error != StateStoreError.None:
    return PreimageTransitionResult[StateStoreSnapshot](status: storeReason(
        current.error)) # A partial/default map cannot authorize writes.
  integratePrepared(state, current.value, data, slot)
