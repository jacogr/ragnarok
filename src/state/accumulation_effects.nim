# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 implications: immutable account writes, yields, provisions and exceptional checkpoints.
## Exposes prepared pairs, guarded current accounts, storage/yield/checkpoint/provision mutations and extraction.
## Guest memory, gas, registers, execution verdicts and publication belong to their caller's PVM layer.

import std/assertions
import ../codec/[bounded, composite, state_outputs, state_accounts, state_layout, state_requests, state_service_values]
import ../chain/parameters
import ../crypto/primitives
import ./[accumulation_context, store, preimages]

type
  AccumulationEffectError* {.pure.} = enum ## No refused/default operation exposes a partial context, fabricated hash or successful empty owner.
    Uninitialized, None, InvalidContexts, InvalidDimension, YieldAbsent, UnknownService,
    NotRequested, AlreadyProvided, InvalidLength, InvalidState, MalformedState, LimitExceeded,
      BackendFailure, InvalidIndex,
      StorageFull,      ## Candidate storage footprint requires more balance than the account has.
      InvalidParameters ## Deposit settings must come from a valid parameter snapshot.
  AccumulationProvisionIndex* = distinct uint64 ## A provision ordinal is neither its target service nor a byte count.
  AccumulationProvisionLimits* = object ## Independent ceilings bound retained records, individual hash/copy work and aggregate payload bytes.
    items*: ElementLimit
    perBlob*, totalBlobBytes*: ByteLimit
  ## Immutable provision backing binds the exact target to its independent raw-byte payload.
  ProvisionData = ref object
    service: ServiceIndex
    bytes: seq[byte]
  AccumulationProvision* = object ## Retained provision owns its original bytes and target; no detached span or caller-selected buffer is accepted.
    data: nil ProvisionData
  AccumulationProvisionInfo* = object ## Copied fixed facts never expose the provision's mutable backing sequence.
    service*: ServiceIndex
    bytes*: int
  ## Immutable set owner lets yield/checkpoint share provision membership without copying its sequence.
  ProvisionSetData = ref object
    values: seq[AccumulationProvision]
    bytes, largest: uint64
  ## Only a present alternative stores a commitment; absence cannot expose a default all-zero hash.
  YieldValue = object
    case present: bool
    of true:
      commitment: OutputCommitment # Zero bytes remain a present protocol value.
    of false:
      discard                      # Absence carries no commitment payload.
  ## Current implications retain separate initial provenance and versioned accounts, yield and provisions.
  EffectData = ref object
    initial: InitialAccumulationContext
    accounts: StateStoreSnapshot
    output: YieldValue
    provisions: ProvisionSetData
  AccumulationEffectContext* = object ## Read-only acyclic context; copies retain a version independently of later effect operations.
    data: nil EffectData
  ## Private pair retains exact initial provenance; neither child refers back to this owner or older pairs.
  PairData = ref object
    source: PreparedAccumulationContexts
    regular, exceptional: AccumulationEffectContext
  AccumulationEffects* = object ## Only prepared initial contexts create a pair; mutations preserve their service/input identity.
    data: nil PairData
  AccumulationStorageChange* = object ## A completed storage mutation owns its successor pair and copied prior-value facts.
    effects*: AccumulationEffects ## Independently retained successor; prior regular/checkpoint owners remain unchanged.
    hadValue*: bool     ## Distinguish an absent key from a present value whose previous length was zero.
    previousBytes*: int ## Previous raw value length; meaningful only when hadValue is true.
  AccumulationEffectInfo* = object ## Copied current facts report retained provisions and the still-empty outgoing transfer sequence.
    service*, nextService*: ServiceIndex
    transfers*, provisions*: int
    hasYield*: bool
  AccumulationEffectResult*[T] = object ## Successful alternatives alone carry complete retained handles, facts or a present yield value.
    case status: AccumulationEffectError
    of None:
      completed: T # Contract-guarded extraction is the only public payload access.
    else:
      discard      # Refusals/defaults carry only their reason.

func error*[T](outcome: AccumulationEffectResult[T]): AccumulationEffectError =
  ## Inspect success/failure without permitting retagging or mutable access.
  outcome.status
func value*[T](outcome: AccumulationEffectResult[T]): T {.inline,
    requires: outcome.status == AccumulationEffectError.None.} =
  ## Extract selected success under compiler/runtime contracts, including optimized execution.
  outcome.completed

proc effectInitialContext*(context: AccumulationEffectContext): AccumulationEffectResult[
    InitialAccumulationContext] =
  ## Retain immutable initial roles, next-ID and input provenance; current accounts use effectAccounts.
  let data = context.data
  if data == nil:
    # A default effect cannot supply another context as a substitute source.
    return AccumulationEffectResult[InitialAccumulationContext](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[InitialAccumulationContext](status: AccumulationEffectError.None,
    completed: data.initial)

proc effectAccounts*(context: AccumulationEffectContext): AccumulationEffectResult[
    StateStoreSnapshot] =
  ## Retain this exact version's current complete account map, independently of initial provenance.
  if context.data == nil:
    return AccumulationEffectResult[StateStoreSnapshot](status:
      AccumulationEffectError.Uninitialized) # No default owner grants a fabricated map.
  AccumulationEffectResult[StateStoreSnapshot](status: AccumulationEffectError.None,
    completed: context.data.accounts)

proc effectInfo*(context: AccumulationEffectContext): AccumulationEffectResult[
    AccumulationEffectInfo] =
  ## Copy current yield-presence and retained service facts, never mutable implication storage.
  let data = context.data
  if data == nil:
    # Missing owners cannot masquerade as valid services with zero effects.
    return AccumulationEffectResult[AccumulationEffectInfo](
        status: AccumulationEffectError.Uninitialized)
  let source = data.initial.contextInfo.value
  AccumulationEffectResult[AccumulationEffectInfo](status: AccumulationEffectError.None,
    completed: AccumulationEffectInfo(service: source.service, nextService: source.nextService,
      transfers: source.transfers, provisions: data.provisions.values.len,
      hasYield: data.output.present))

proc effectYield*(context: AccumulationEffectContext): AccumulationEffectResult[OutputCommitment] =
  ## Read a present yield by value; default and absent alternatives never return a fake zero commitment.
  let data = context.data
  if data == nil:
    # Default contexts have no selected yield state.
    return AccumulationEffectResult[OutputCommitment](status: AccumulationEffectError.Uninitialized)
  if not data.output.present:
    # A successfully prepared context may legitimately have no yield yet.
    return AccumulationEffectResult[OutputCommitment](status: AccumulationEffectError.YieldAbsent)
  AccumulationEffectResult[OutputCommitment](status: AccumulationEffectError.None,
    completed: data.output.commitment)

proc effectContext*(effects: AccumulationEffects, dimension: AccumulationDimension):
    AccumulationEffectResult[AccumulationEffectContext] =
  ## Select one exact version; invalid enum casts cannot silently alias the exceptional dimension.
  if ord(dimension) < ord(AccumulationDimension.Regular) or ord(dimension) > ord(
      AccumulationDimension.Exceptional):
    # Reject unsupported dimensions before selecting any retained child.
    return AccumulationEffectResult[AccumulationEffectContext](
        status: AccumulationEffectError.InvalidDimension)
  let data = effects.data
  if data == nil:
    # Default pairs are not initialized I squared values.
    return AccumulationEffectResult[AccumulationEffectContext](
        status: AccumulationEffectError.Uninitialized)
  let selected = if dimension == AccumulationDimension.Regular: data.regular
    else: data.exceptional # Only the two validated dimensions remain.
  AccumulationEffectResult[AccumulationEffectContext](status: AccumulationEffectError.None,
    completed: selected)

proc effectsSource*(effects: AccumulationEffects): AccumulationEffectResult[
    PreparedAccumulationContexts] =
  ## Retain original prepared provenance independently of effect versions and checkpoint lifetimes.
  let data = effects.data
  if data == nil:
    # No default pair may grant an initialized preparation certificate.
    return AccumulationEffectResult[PreparedAccumulationContexts](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[PreparedAccumulationContexts](status: AccumulationEffectError.None,
    completed: data.source)

proc prepareAccumulationEffects*(contexts: PreparedAccumulationContexts): AccumulationEffectResult[
    AccumulationEffects] =
  ## Begin at the actual initial I in both dimensions; no caller-selected replacement state or yield is accepted.
  let initial = contexts.initialContext(AccumulationDimension.Regular)
  if initial.error != AccumulationContextError.None:
    # Only successfully prepared immutable contexts can authorize host state effects.
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.InvalidContexts)
  let current = AccumulationEffectContext(data: EffectData(initial: initial.value,
    accounts: initial.value.contextAccounts.value, output: YieldValue(present: false),
        provisions: ProvisionSetData(values: @[], bytes: 0, largest: 0)))
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: contexts, regular: current,
        exceptional: current)))

proc recordAccumulationYield*(effects: AccumulationEffects, commitment: OutputCommitment):
    AccumulationEffectResult[AccumulationEffects] =
  ## Apply only the state part of a validated yield call: replace regular yield, preserving the checkpoint.
  ## The host dispatcher must first charge gas/read guest memory; failures there must not call this operation.
  let data = effects.data
  if data == nil:
    # Refuse before constructing a partially initialized regular context.
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.Uninitialized)
  let previous = data.regular.data
  assert previous != nil # Private construction preserves initialized children for every published pair.
  let current = AccumulationEffectContext(data: EffectData(initial: previous.initial,
    accounts: previous.accounts, output: YieldValue(present: true, commitment: commitment),
        provisions: previous.provisions))
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

proc checkpointAccumulationEffects*(effects: AccumulationEffects): AccumulationEffectResult[
    AccumulationEffects] =
  ## Apply only checkpoint's implication assignment Y'=X; later regular changes cannot alter the retained snapshot.
  ## Guest gas/r7 handling is outside this state-only operation; no implicit checkpoint occurs on yield.
  let data = effects.data
  if data == nil:
    # A checkpoint cannot turn an uninitialized pair into successful empty implications.
    return AccumulationEffectResult[AccumulationEffects](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: data.regular,
      exceptional: data.regular)))

proc effectProvisionAt*(context: AccumulationEffectContext, index: AccumulationProvisionIndex):
    AccumulationEffectResult[AccumulationProvision] =
  ## Retain one provision only after checking its ordinal against this exact immutable context.
  let data = context.data
  if data == nil:
    # Default contexts contain no validated provision sequence.
    return AccumulationEffectResult[AccumulationProvision](
        status: AccumulationEffectError.Uninitialized)
  if uint64(index) >= uint64(data.provisions.values.len):
    # Prove the full-width ordinal before narrowing or accessing the retained sequence.
    return AccumulationEffectResult[AccumulationProvision](
        status: AccumulationEffectError.InvalidIndex)
  AccumulationEffectResult[AccumulationProvision](status: AccumulationEffectError.None,
    completed: data.provisions.values[int(uint64(index))])

proc provisionInfo*(provision: AccumulationProvision): AccumulationEffectResult[
    AccumulationProvisionInfo] =
  ## Copy the exact target and length from one owner-bound provision; default handles are not empty blobs.
  let data = provision.data
  if data == nil:
    # A default provision cannot fabricate target zero or a valid zero-byte payload.
    return AccumulationEffectResult[AccumulationProvisionInfo](
        status: AccumulationEffectError.Uninitialized)
  AccumulationEffectResult[AccumulationProvisionInfo](status: AccumulationEffectError.None,
    completed: AccumulationProvisionInfo(service: data.service, bytes: data.bytes.len))

proc copyProvisionBytes*(provision: AccumulationProvision): AccumulationEffectResult[seq[byte]] =
  ## Return independent bytes from the retained provision; caller mutations never affect later extraction/checkpoints.
  let data = provision.data
  if data == nil:
    # Empty successful payloads require an actual validated owner.
    return AccumulationEffectResult[seq[byte]](status: AccumulationEffectError.Uninitialized)
  var bytes = newSeq[byte](data.bytes.len)
  # Exact retained length was bounded before construction; copy without exporting shared mutable storage.
  for i, octet in data.bytes: bytes[i] = octet
  AccumulationEffectResult[seq[byte]](status: AccumulationEffectError.None, completed: bytes)

proc recordAccumulationProvision*(effects: AccumulationEffects, service: ServiceIndex,
    bytes: openArray[byte], limits: AccumulationProvisionLimits): AccumulationEffectResult[
        AccumulationEffects] =
  ## Retain a requested target/blob pair in regular implications only, with WHO/HUH-style protocol refusals.
  ## Stable bytes are borrowed during the call; accepted bytes are independently owned. Guest gas/memory checks precede this API.
  ## All refusals preserve the caller's pair and expose no partially captured provision.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # No default pair authorizes account lookup or retained bytes.
  let previous = data.regular.data
  assert previous != nil # Only private constructors publish initialized children.
  let size = uint64(bytes.len)
  if size > uint64(high(uint32)):
    fail(AccumulationEffectError.InvalidLength) # Keep the pinned request-length domain without namespace restrictions.
  if size > uint64(limits.perBlob) or previous.provisions.largest > uint64(limits.perBlob) or
      previous.provisions.bytes > uint64(limits.totalBlobBytes) or
      uint64(previous.provisions.values.len) > uint64(limits.items):
    fail(AccumulationEffectError.LimitExceeded) # Bound hash/scan work and validate retained-prefix policy before new work.
  let state = previous.accounts
  let account = state.lookup(chapterServiceKey(StateChapter(255), service))
  if account.error == StateStoreError.MissingKey:
    fail(AccumulationEffectError.UnknownService) # Orphan request records do not create a target account.
  if account.error != StateStoreError.None:
    fail(AccumulationEffectError.InvalidState) # Default/corrupt backing cannot fabricate WHO or HUH.
  let digest = blake2b256(bytes)
  if digest.error != CryptoError.None:
    fail(AccumulationEffectError.BackendFailure) # No failed hash becomes an unrequested verdict.
  let requested = preimageRequested(state, service, ServicePreimageHash(array[32, byte](
      digest.value)),
    RequestLength(uint32(size)))
  if requested.error == PreimageTransitionError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Preserve canonical namespace failures separately.
  if requested.error == PreimageTransitionError.MalformedState:
    fail(AccumulationEffectError.MalformedState) # Never normalize malformed account/history bytes into ordinary HUH.
  if requested.error != PreimageTransitionError.None:
    fail(AccumulationEffectError.InvalidState) # Only a complete canonical query can authorize provision capture.
  if not requested.value:
    fail(AccumulationEffectError.NotRequested) # Only the exact outstanding (hash,length) request is eligible.
  # Equality is target plus complete raw bytes, not hash-only equality or an unrelated owner's coordinates.
  for provision in previous.provisions.values:
    let retained = provision.data
    assert retained != nil # Published provision sequences contain initialized owners only.
    if uint32(retained.service) == uint32(service) and retained.bytes == bytes:
      fail(AccumulationEffectError.AlreadyProvided) # Duplicate refusal requires no additional record capacity.
  if uint64(previous.provisions.values.len) >= uint64(limits.items) or
      previous.provisions.values.len >= high(int) div sizeof(AccumulationProvision) or
      size > uint64(limits.totalBlobBytes)-previous.provisions.bytes:
    fail(AccumulationEffectError.LimitExceeded) # Prove count/native extent and aggregate addition before allocation.
  var owned = newSeq[byte](bytes.len)
  # Borrowed caller bytes become immutable private storage before any successful pair is published.
  for i, octet in bytes: owned[i] = octet
  var provisions = newSeq[AccumulationProvision](previous.provisions.values.len+1)
  # Share only immutable prior provision owners; no new version links back to its parent effect pair.
  for i, provision in previous.provisions.values: provisions[i] = provision
  provisions[previous.provisions.values.len] = AccumulationProvision(data: ProvisionData(
      service: service, bytes: owned))
  let current = AccumulationEffectContext(data: EffectData(initial: previous.initial,
    accounts: previous.accounts, output: previous.output, provisions: ProvisionSetData(
      values: provisions,
      bytes: previous.provisions.bytes+size,
      largest: max(previous.provisions.largest, size))))
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

## Subtract an exact 128-bit product from a budget of at most 2^65-2 tokens.
## Limb products and their carry sums are bounded before arithmetic; no saturation impersonates equality.
proc consumeDeposit(low, upper: var uint64, count, rate: uint64): bool =
  let mask = 0xffffffff'u64
  let p0 = (count and mask)*(rate and mask)
  let p1 = (count and mask)*(rate shr 32)
  let p2 = (count shr 32)*(rate and mask)
  let p3 = (count shr 32)*(rate shr 32)
  let middle = (p0 shr 32)+(p1 and mask)+(p2 and mask) # Below 3*2^32.
  let productLow = ((middle and mask) shl 32) or (p0 and mask)
  let productHigh = p3+(p1 shr 32)+(p2 shr 32)+(middle shr 32) # Exact high half of a uint64 product.
  if productHigh > upper or (productHigh == upper and productLow > low):
    return false # The mathematical deposit exceeds the remaining balance plus gratis.
  if productLow > low:
    upper = upper-productHigh-1 # Comparison proves the borrow exists.
    low = high(uint64)-productLow+low+1 # productLow>low proves no intermediate overflow.
  else:
    upper -= productHigh # No low-limb borrow.
    low -= productLow
  true

## Compare threshold to balance using the equivalent deposit <= balance+gratis equation.
## Even full-width configured rates and footprint fields cannot overflow this comparison.
proc funded(metadata: ServiceMetadata, parameters: Parameters): bool =
  let balance = uint64(metadata.balance)
  let gratis = uint64(metadata.depositOffset)
  var low = 0'u64
  var upper = 0'u64
  if gratis > high(uint64)-balance:
    upper = 1 # Preserve the 65th bit of available balance plus gratis.
    low = gratis-(high(uint64)-balance)-1
  else:
    low = balance+gratis # Proven representable before addition.
  for term in [(1'u64, parameters.get(depositPerAccount)),
      (uint64(metadata.storageItems), parameters.get(depositPerItem)),
      (uint64(metadata.storageBytes), parameters.get(depositPerByte))]:
    let (count, rate) = term # Each independent term consumes the remaining exact two-limb budget.
    if not consumeDeposit(low, upper, count, rate):
      return false # FULL includes products larger than the complete available budget.
  true

proc recordAccumulationStorage*(effects: AccumulationEffects, key, value: openArray[byte],
    parameters: Parameters, limit: ByteLimit): AccumulationEffectResult[AccumulationStorageChange] =
  ## Apply one raw self-storage mutation atomically, retaining both initial provenance and checkpoint.
  ## Borrowed bytes remain stable during this call; the complete-map store independently captures accepted values.
  ## Empty values delete the key. Success retains the successor and distinguishes absent/present-empty prior values.
  ## StorageFull is a funding refusal; copy/store limits, malformed counters and backend failure publish no successor.
  # Refuse without publishing a candidate map or successor effect pair.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationStorageChange](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Default pairs cannot authorize mutations.
  if not parameters.valid:
    fail(AccumulationEffectError.InvalidParameters) # No default deposit schedule is accepted.
  if uint64(key.len) > uint64(limit) or uint64(value.len) > uint64(limit):
    fail(AccumulationEffectError.LimitExceeded) # Bound both borrowed extents before hashing/allocation.
  let previous = data.regular.data
  assert previous != nil # Private constructors retain complete current account snapshots.
  let service = previous.initial.contextInfo.value.service
  let accountKey = chapterServiceKey(StateChapter(255), service)
  let account = previous.accounts.lookup(accountKey)
  if account.error != StateStoreError.None or account.value.byteLength != ServiceMetadataBytes:
    fail(AccumulationEffectError.MalformedState) # Self must have complete canonical metadata.
  let decoded = decodeServiceMetadata(account.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    fail(AccumulationEffectError.MalformedState) # Never repair corrupt metadata as a side effect.
  var metadata = decoded.value.metadata
  let derived = serviceStorageKey(service, key, limit)
  if derived.error != ServiceValueError.None:
    fail(AccumulationEffectError.BackendFailure) # No alternate namespace on failed hashing.
  let old = previous.accounts.lookup(derived.value)
  if old.error notin {StateStoreError.None, StateStoreError.MissingKey}:
    fail(AccumulationEffectError.InvalidState) # No fabricated absent value from an invalid map.
  let hadValue = old.error == StateStoreError.None
  let oldBytes = (if hadValue: old.value.byteLength else: 0)
  var items = uint64(metadata.storageItems)
  var octets = uint64(metadata.storageBytes)
  if hadValue:
    # Remove the old footprint before adding a replacement; bounded native key/value lengths fit uint64.
    if uint64(key.len) > high(uint64)-34-uint64(oldBytes):
      fail(AccumulationEffectError.InvalidState) # Prove footprint addition before forming it.
    let footprint = 34'u64+uint64(key.len)+uint64(oldBytes)
    if items == 0 or octets < footprint:
      fail(AccumulationEffectError.MalformedState) # Inconsistent stored counters never underflow.
    items -= 1
    octets -= footprint
  if value.len != 0:
    # A nonempty value inserts one item; an empty value deletes, including absent-key no-ops.
    if uint64(key.len) > high(uint64)-34-uint64(value.len):
      fail(AccumulationEffectError.InvalidState) # Full-width native extents cannot wrap a footprint.
    let footprint = 34'u64+uint64(key.len)+uint64(value.len)
    if items == uint64(high(uint32)) or footprint > high(uint64)-octets:
      fail(AccumulationEffectError.InvalidState) # Preserve declared E4/E8 footprint domains without wrapping.
    items += 1
    octets += footprint
  metadata.storageItems = AccountStorageItems(uint32(items))
  metadata.storageBytes = AccountStorageBytes(octets)
  if not funded(metadata, parameters):
    fail(AccumulationEffectError.StorageFull) # FULL preserves the original map even for an underfunded deletion.
  let encoded = serviceMetadataEntry(service, metadata, ByteLimit(ServiceMetadataBytes)).value
  var owned = newSeq[byte](value.len)
  for i, octet in value:
    owned[i] = octet # Capture caller bytes before publishing an immutable map.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([StateWrite(key: accountKey, kind: StateWriteKind.Put,
      value: encoded.value), StateWrite(key: derived.value,
      kind: (if value.len == 0: StateWriteKind.Delete else: StateWriteKind.Put), value: owned)])
  case changed.error
  of StateStoreError.None:
    discard # Publish only after both metadata and storage changes pass all inherited store ceilings.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Local map policy cannot masquerade as protocol FULL.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Merklization failure leaves the source owner untouched.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial successor on any store invariant failure.
  let current = AccumulationEffectContext(data: EffectData(initial: previous.initial,
    accounts: changed.value, output: previous.output, provisions: previous.provisions))
  let successor = AccumulationEffects(data: PairData(source: data.source, regular: current,
    exceptional: data.exceptional))
  AccumulationEffectResult[AccumulationStorageChange](status: AccumulationEffectError.None,
    completed: AccumulationStorageChange(effects: successor, hadValue: hadValue,
      previousBytes: oldBytes))
