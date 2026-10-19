# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 implications: immutable account/queue/staging/privilege writes, yields, provisions, deferred transfers and exceptional checkpoints.
## Exposes prepared pairs, guarded current accounts/info/queues/staging/privileges and controlled mutations with a versioned allocation cursor.
## Guest memory, gas, registers, execution verdicts and publication belong to their caller's PVM layer.

import std/[assertions, algorithm]
import ../codec/[bounded, composite, state_outputs, state_accounts, state_layout, state_requests,
    state_service_values, state_privileges, state_authorization, work_report, state_safrole, c2_records]
import ../chain/parameters
import ../crypto/primitives
import ./[accumulation_context, accumulation_invocation, store, preimages]

const AccumulationAccountInfoBytes* = 96 ## Fixed Omega_I record, excluding serialized metadata's version byte.

type
  AccumulationEffectError* {.pure.} = enum ## No refused/default operation exposes a partial context, fabricated hash or successful empty owner.
    Uninitialized, None, InvalidContexts, InvalidDimension, YieldAbsent, UnknownService,
    NotRequested, AlreadyProvided, InvalidLength, InvalidState, MalformedState, LimitExceeded,
      BackendFailure, InvalidIndex,
      StorageFull,           ## Candidate storage footprint requires more balance than the account has.
      InvalidParameters,     ## Deposit settings must come from a valid parameter snapshot.
      NotManager,            ## Only the current privileged manager may replace the privilege state.
      AmbiguousPrivileges,   ## Conflicting gas values for one service have no pinned dictionary interpretation.
      InvalidCore,           ## The selected core is outside the current positional queue layout.
      NotAssigner,           ## Only the current assigner may replace its core queue.
      InvalidValidatorCount, ## Staging population must be a supported multiple of three.
      NotDelegator,          ## Only the current delegator may replace the staging roster.
      InsufficientCash,      ## Account debits must preserve the creator's own minimum balance.
      ServiceExists,         ## A registrar-selected reserved service ID is already occupied.
      TransferGasLow         ## Offered deferred gas is below the current destination minimum.
  AccumulationTransferDestination* = distinct uint64 ## Full register domain; high bits are rejected as WHO before narrowing to ServiceIndex.
  AccumulationTransferIndex* = distinct uint64 ## Outgoing ordinal is neither a service identity nor a transfer amount.
  # Immutable ordered transfer backing is shared only by frozen effect versions.
  TransferSetData = ref object
    values: seq[DeferredTransfer]
  AccumulationDesiredService* = distinct uint64 ## Full-width proposal: only registrar values below 65536 select a reserved uint32 ID.
  AccumulationNewService* = object ## Copied creation proposal; account identity, parent, slot and starting balance are derived by the state operation.
    codeHash*: CodeHash     ## Raw offered hash; creation neither requires nor publishes its preimage.
    length*: RequestLength  ## The advertised code request length retains the entire E4 domain.
    accumulationGas*: Gas   ## Minimum per-item gas, without signed narrowing.
    transferGas*: Gas       ## Minimum per-transfer gas, without signed narrowing.
    gratis*: AccountBalance ## Nonzero offset requires the current manager.
    desired*: AccumulationDesiredService ## Non-registrar or non-reserved proposals select automatic allocation.
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
  EffectData = ref object # Current implications retain separate initial provenance, accounts, yield, provisions and transfers.
    initial: InitialAccumulationContext
    accounts: StateStoreSnapshot
    nextService: ServiceIndex
    staging: ValidatorStateSnapshot
    queues: AuthorizationSnapshot
    privileges: PrivilegeSnapshot
    output: YieldValue
    provisions: ProvisionSetData
    transfers: TransferSetData
  AccumulationEffectContext* = object ## Read-only acyclic context; copies retain a version independently of later effect operations.
    data: nil EffectData
  ## Private pair retains exact initial provenance; neither child refers back to this owner or older pairs.
  PairData = ref object
    source: PreparedAccumulationContexts
    regular, exceptional: AccumulationEffectContext
  AccumulationEffects* = object ## Only prepared initial contexts create a pair; mutations preserve their service/input identity.
    data: nil PairData
  # Acyclic immutable plan retains its exact source pair and copied prospective debit/transfer.
  TransferPlanData = ref object
    source: AccumulationEffects
    metadata: ServiceMetadata
    transfer: DeferredTransfer
  PreparedAccumulationTransfer* = object ## Pure validated transfer; only commit can publish against this plan's retained source version.
    data: nil TransferPlanData
  AccumulationStorageChange* = object ## A completed storage mutation owns its successor pair and copied prior-value facts.
    effects*: AccumulationEffects ## Independently retained successor; prior regular/checkpoint owners remain unchanged.
    hadValue*: bool     ## Distinguish an absent key from a present value whose previous length was zero.
    previousBytes*: int ## Previous raw value length; meaningful only when hadValue is true.
  AccumulationServiceChange* = object ## A completed creation owns both its successor and the exact selected service ID.
    effects*: AccumulationEffects ## Current accounts and allocation cursor advance together; older versions remain valid.
    service*: ServiceIndex ## Reserved or automatic ID actually created by this operation.
  AccumulationEffectInfo* = object ## Copied current facts report retained outgoing transfers, provisions and service/cursor identity.
    service*: ServiceIndex ## The invoking service retains its initial identity.
    nextService*: ServiceIndex ## Current allocation cursor; historical initial provenance remains separate.
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

# Build an unpublished successor sharing frozen components; each operation replaces only its selected fields.
proc successorData(previous: EffectData, accounts: StateStoreSnapshot): EffectData =
  EffectData(initial: previous.initial, accounts: accounts, nextService: previous.nextService,
    staging: previous.staging, queues: previous.queues, privileges: previous.privileges,
    output: previous.output, provisions: previous.provisions, transfers: previous.transfers)

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

proc effectPrivileges*(context: AccumulationEffectContext): AccumulationEffectResult[
    PrivilegeSnapshot] =
  ## Retain this version's exact current roles and allowances, independently of historical initial privileges.
  if context.data == nil:
    return AccumulationEffectResult[PrivilegeSnapshot](status:
      AccumulationEffectError.Uninitialized) # No fabricated default manager or empty dictionary.
  AccumulationEffectResult[PrivilegeSnapshot](status: AccumulationEffectError.None,
    completed: context.data.privileges)

proc effectQueues*(context: AccumulationEffectContext): AccumulationEffectResult[
    AuthorizationSnapshot] =
  ## Retain this exact version's ordered queues; initial provenance remains independently available.
  if context.data == nil:
    return AccumulationEffectResult[AuthorizationSnapshot](
        status: AccumulationEffectError.Uninitialized) # Defaults grant no queue owner.
  AccumulationEffectResult[AuthorizationSnapshot](status: AccumulationEffectError.None,
    completed: context.data.queues)

proc effectStaging*(context: AccumulationEffectContext): AccumulationEffectResult[
    ValidatorStateSnapshot] =
  ## Retain this version's exact ordered staging roster independently of initial population and later effects.
  if context.data == nil:
    return AccumulationEffectResult[ValidatorStateSnapshot](
        status: AccumulationEffectError.Uninitialized) # Defaults grant no staging owner.
  AccumulationEffectResult[ValidatorStateSnapshot](status: AccumulationEffectError.None,
    completed: context.data.staging)

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
    completed: AccumulationEffectInfo(service: source.service, nextService: data.nextService,
      transfers: data.transfers.values.len, provisions: data.provisions.values.len,
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
    accounts: initial.value.contextAccounts.value,
    nextService: initial.value.contextInfo.value.nextService,
    staging: initial.value.contextStaging.value, queues: initial.value.contextQueues.value,
    privileges: initial.value.contextPrivileges.value,
    output: YieldValue(present: false), transfers: TransferSetData(values: @[]),

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
  let candidate = successorData(previous, previous.accounts)
  candidate.output = YieldValue(present: true, commitment: commitment)
  let current = AccumulationEffectContext(data: candidate)
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
  let candidate = successorData(previous, previous.accounts)
  candidate.provisions = ProvisionSetData(values: provisions,
    bytes: previous.provisions.bytes+size, largest: max(previous.provisions.largest, size))
  let current = AccumulationEffectContext(data: candidate)
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

## Consume the same exact three deposit terms for both funding and minimum-balance queries.
proc consumeAccountDeposit(metadata: ServiceMetadata, parameters: Parameters,
    low, upper: var uint64): bool =
  for term in [(1'u64, parameters.get(depositPerAccount)),
      (uint64(metadata.storageItems), parameters.get(depositPerItem)),
      (uint64(metadata.storageBytes), parameters.get(depositPerByte))]:
    let (count, rate) = term # Each independent term consumes the remaining exact two-limb budget.
    if not consumeDeposit(low, upper, count, rate):
      return false # FULL includes products larger than the complete available budget.
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
  consumeAccountDeposit(metadata, parameters, low, upper)

proc effectAccountInfo*(context: AccumulationEffectContext, service: ServiceIndex,
    parameters: Parameters): AccumulationEffectResult[array[AccumulationAccountInfoBytes, byte]] =
  ## Encode this version's complete account into the fixed Omega_I wire record.
  ## Refused/default queries contain only a reason; no caller-selected account or fabricated bytes escape.
  ## The fixed record includes computed minimum balance and has no metadata version byte.
  ## UnknownService, invalid parameters and unencodable/malformed fields remain explicit guarded failures.
  # Retain no partial record on invalid provenance, missing accounts or malformed dependent values.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[array[AccumulationAccountInfoBytes, byte]](status: reason)
  let data = context.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Default versions cannot authorize account queries.
  if not parameters.valid:
    fail(AccumulationEffectError.InvalidParameters) # No substituted default deposit configuration.
  let found = data.accounts.lookup(chapterServiceKey(StateChapter(255), service))
  if found.error == StateStoreError.MissingKey:
    fail(AccumulationEffectError.UnknownService) # Protocol NONE is selected only by a complete-map absence.
  if found.error != StateStoreError.None:
    fail(AccumulationEffectError.InvalidState) # Invalid owners cannot fabricate absent accounts.
  if found.value.byteLength != ServiceMetadataBytes:
    fail(AccumulationEffectError.MalformedState) # Bound the entire metadata copy before allocation.
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    fail(AccumulationEffectError.MalformedState) # Require the one complete canonical version-zero schema.
  let metadata = decoded.value.metadata
  let gratis = uint64(metadata.depositOffset)
  var low = high(uint64)
  var upper = 0'u64
  if gratis != 0:
    upper = 1 # UINT64_MAX+gratis has this exact two-limb representation.
    low = gratis-1
  if not consumeAccountDeposit(metadata, parameters, low, upper):
    fail(AccumulationEffectError.MalformedState) # Deposit>UINT64_MAX+gratis implies an unencodable E8 threshold.
  # Remaining budget is UINT64_MAX+gratis-deposit; subtract from UINT64_MAX only when nonnegative.
  let minimum = (if upper != 0 or low == high(uint64): 0'u64 else: high(uint64)-low)
  var bytes = default(array[AccumulationAccountInfoBytes, byte])
  let hash = array[32, byte](metadata.codeHash)
  for i in 0..<32:
    bytes[i] = hash[i] # Raw hash has no version, count or prefix.
  for field, value in [uint64(metadata.balance), minimum, uint64(metadata.minimumAccumulationGas),
      uint64(metadata.minimumTransferGas), uint64(metadata.storageBytes)]:
    for i in 0..<8:
      bytes[32+field*8+i] = byte((value shr (8*i)) and 255) # Five exact E8 values occupy bytes32..71.
  for i in 0..<4:
    bytes[72+i] = byte((uint32(metadata.storageItems) shr (8*i)) and 255) # Items alone use E4 before gratis.
  for i in 0..<8:
    bytes[76+i] = byte((gratis shr (8*i)) and 255) # Preserve all gratis bits after the E4 item field.
  for field, value in [uint32(metadata.created), uint32(metadata.lastAccumulation), uint32(
      metadata.parent)]:
    for i in 0..<4:
      bytes[84+field*4+i] = byte((value shr (8*i)) and 255) # Exact E4 slots/parent finish the fixed record.
  AccumulationEffectResult[array[AccumulationAccountInfoBytes, byte]](
    status: AccumulationEffectError.None, completed: bytes)

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
  let candidate = successorData(previous, changed.value)
  let current = AccumulationEffectContext(data: candidate)
  let successor = AccumulationEffects(data: PairData(source: data.source, regular: current,
    exceptional: data.exceptional))
  AccumulationEffectResult[AccumulationStorageChange](status: AccumulationEffectError.None,
    completed: AccumulationStorageChange(effects: successor, hadValue: hadValue,
      previousBytes: oldBytes))

# Numeric order canonicalizes the host's set independently of little-endian wire ordering.
func comparePrivilege(left, right: AlwaysAccumulate): int =
  if uint32(left.service) < uint32(right.service): return -1 # Smaller service precedes larger service.
  if uint32(left.service) > uint32(right.service): return 1 # No subtraction or signed narrowing.
  if uint64(left.gas) < uint64(right.gas): return -1 # Group identical pairs for set deduplication.
  if uint64(left.gas) > uint64(right.gas): return 1 # Preserve distinct gas values for explicit ambiguity refusal.
  0

proc recordAccumulationBless*(effects: AccumulationEffects, source: PrivilegeState,
    config: PrivilegeConfig): AccumulationEffectResult[AccumulationEffects] =
  ## Replace regular privileges only for the current manager, preserving accounts, yield, provisions and checkpoint.
  ## Borrowed sequences stay stable during this call; accepted canonical bytes and snapshot own independent copies.
  ## Identical pairs are set duplicates; conflicting gas for a service refuses explicitly as AmbiguousPrivileges.
  # No partially encoded map or privilege owner escapes refusal.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Default pairs cannot authorize manager operations.
  let previous = data.regular.data
  assert previous != nil # Private effect constructors retain initialized current snapshots.
  let current = previous.privileges.privilegeInfo
  if current.error != PrivilegeError.None:
    fail(AccumulationEffectError.InvalidState) # Invalid owners cannot fabricate authority.
  if uint32(previous.initial.contextInfo.value.service) != uint32(current.value.manager):
    fail(AccumulationEffectError.NotManager) # Authorization precedes proposed role/dictionary validation.
  if uint64(config.cores) != uint64(current.value.cores) or source.assigners.len !=
      current.value.cores:
    fail(AccumulationEffectError.InvalidState) # The current profile fixes the exact positional assigner count.
  if uint64(source.always.len) > uint64(config.maxAlways) or
      source.always.len > high(int) div sizeof(AlwaysAccumulate):
    fail(AccumulationEffectError.LimitExceeded) # Bound raw pair sorting/capture even when many entries would deduplicate.
  var ordered = newSeq[AlwaysAccumulate](source.always.len)
  for i, pair in source.always:
    ordered[i] = pair # Never sort or mutate the caller's borrowed sequence.
  ordered.sort(comparePrivilege)
  var unique: seq[AlwaysAccumulate] = @[]
  for pair in ordered:
    if unique.len != 0 and uint32(unique[unique.len-1].service) == uint32(pair.service):
      if uint64(unique[unique.len-1].gas) != uint64(pair.gas):
        fail(AccumulationEffectError.AmbiguousPrivileges) # No arbitrary first/last/max allowance interpretation.
      continue # Identical raw pairs are one member of the pinned set comprehension.
    unique.add(pair) # Prior item/native extent bounds also authorize this canonical subset.
  let canonical = PrivilegeState(manager: source.manager, delegator: source.delegator,
    registrar: source.registrar, assigners: source.assigners, always: unique)
  let encoded = privilegeStateEntry(canonical, config)
  if encoded.error in {PrivilegeError.LimitExceeded, PrivilegeError.LengthOverflow}:
    fail(AccumulationEffectError.LimitExceeded) # Codec byte/item ceilings are local, never HUH or WHO.
  if encoded.error != PrivilegeError.None:
    fail(AccumulationEffectError.InvalidState) # No invalid configuration or malformed canonical dictionary is accepted.
  let decoded = decodePrivilegeState(encoded.value.value, config)
  if decoded.error != PrivilegeError.None:
    fail(AccumulationEffectError.InvalidState) # Encoding must supply exactly one independently owned canonical snapshot.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([StateWrite(key: encoded.value.key, kind: StateWriteKind.Put,
    value: encoded.value.value)])
  case changed.error
  of StateStoreError.None:
    discard # C(12) and the typed privilege snapshot publish only after complete Merklization.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Inherited complete-map limits remain independent of protocol gas.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Prior accounts and privileges survive failed hashing.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial map survives any other store invariant failure.
  let candidate = successorData(previous, changed.value)
  candidate.privileges = decoded.value.snapshot
  let currentContext = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: currentContext,
      exceptional: data.exceptional)))

proc recordAccumulationAssign*(effects: AccumulationEffects, core: AuthorizationCoreIndex,
    queue: openArray[AuthorizerHash], assigner: ServiceIndex, queues: AuthorizationConfig,
    privileges: PrivilegeConfig): AccumulationEffectResult[AccumulationEffects] =
  ## Replace one current queue and its assigner atomically, retaining the exceptional checkpoint.
  ## Borrowed hashes stay stable during this call; success owns independent canonical snapshots.
  ## Core/authority refusals precede candidate validation; local limits/backend failures expose no successor.
  # No candidate map or typed owner escapes a refusal.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Defaults cannot authorize queue replacement.
  let previous = data.regular.data
  assert previous != nil # Every private pair retains complete children.
  let info = previous.privileges.privilegeInfo.value
  if uint64(core) >= uint64(info.cores):
    fail(AccumulationEffectError.InvalidCore) # Bound the nominal core before native narrowing.
  let selected = int(uint64(core))
  if uint32(previous.initial.contextInfo.value.service) != uint32(
      previous.privileges.privilegeAssignerAt(PrivilegeCoreIndex(uint64(core))).value):
    fail(AccumulationEffectError.NotAssigner) # Current authority, never initial roles, governs handoff.
  if queue.len != 80 or uint64(queues.cores) != uint64(info.cores) or
      uint64(privileges.cores) != uint64(info.cores) or
      previous.queues.authorizationCores.value != info.cores:
    fail(AccumulationEffectError.InvalidState) # Exact positional layouts must agree before capture.
  let cores = uint64(info.cores)
  if cores > uint64(queues.maxHashes) div 80 or cores > uint64(queues.maxBytes) div 2560 or
      cores > uint64(high(int) div 2560) or
      uint64(info.always) > uint64(privileges.maxAlways) or
      info.always > high(int) div sizeof(AlwaysAccumulate):
    fail(AccumulationEffectError.LimitExceeded) # Prove total hash/byte/native extents before allocations.
  var rows = newSeq[AuthorizerRow](info.cores)
  var roles = PrivilegeState(manager: info.manager, delegator: info.delegator,
    registrar: info.registrar, assigners: newSeq[ServiceIndex](info.cores),
    always: newSeq[AlwaysAccumulate](info.always))
  for c in 0..<info.cores:
    rows[c] = newSeq[AuthorizerHash](80) # Fixed per-core length and total extents are already bounded.
    roles.assigners[c] = previous.privileges.privilegeAssignerAt(PrivilegeCoreIndex(uint64(c))).value
    for i in 0..<80:
      rows[c][i] = (if c == selected: queue[i] else:
        previous.queues.authorizerAt(AuthorizationCoreIndex(uint64(c)), AuthorizationIndex(uint64(
            i))).value) # Preserve every other positional hash.
  roles.assigners[selected] = assigner
  for i in 0..<info.always:
    roles.always[i] = previous.privileges.alwaysAccumulateAt(PrivilegeEntryIndex(uint64(
        i))).value # Preserve canonical numeric dictionary order.
  let encodedQueues = authorizationEntry(AuthorizationKind.Queues, rows, queues)
  let encodedRoles = privilegeStateEntry(roles, privileges)
  if encodedQueues.error in {AuthorizationError.LimitExceeded, AuthorizationError.LengthOverflow} or
      encodedRoles.error in {PrivilegeError.LimitExceeded, PrivilegeError.LengthOverflow}:
    fail(AccumulationEffectError.LimitExceeded) # Component policies remain independent of guest success.
  if encodedQueues.error != AuthorizationError.None or encodedRoles.error != PrivilegeError.None:
    fail(AccumulationEffectError.InvalidState) # Never publish an invalid candidate profile.
  let nextQueues = decodeAuthorization(AuthorizationKind.Queues, encodedQueues.value.value, queues)
  let nextRoles = decodePrivilegeState(encodedRoles.value.value, privileges)
  if nextQueues.error != AuthorizationError.None or nextRoles.error != PrivilegeError.None:
    fail(AccumulationEffectError.InvalidState) # Require complete independent typed owners before publication.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([
    StateWrite(key: encodedQueues.value.key, kind: StateWriteKind.Put,
        value: encodedQueues.value.value),
    StateWrite(key: encodedRoles.value.key, kind: StateWriteKind.Put,
        value: encodedRoles.value.value)])
  case changed.error
  of StateStoreError.None:
    discard # Both chapters have one fully Merklized successor.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Inherited store ceilings never produce a guest code.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Original accounts and both typed owners survive hash failure.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial candidate escapes other invariant failures.
  let candidate = successorData(previous, changed.value)
  candidate.queues = nextQueues.value.snapshot
  candidate.privileges = nextRoles.value.snapshot
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

proc recordAccumulationDesignate*(effects: AccumulationEffects, validators: openArray[
    StateValidator], config: ValidatorStateConfig): AccumulationEffectResult[AccumulationEffects] =
  ## Replace the complete regular staging roster only for the current delegator, preserving the checkpoint.
  ## Borrowed records stay stable during this call; accepted canonical bytes and typed snapshot own their copies.
  ## InvalidValidatorCount/NotDelegator are protocol refusals; component/store/backend failures expose no successor.
  # Refuse before publishing a partial map or roster owner.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Default pairs cannot authorize delegation.
  let previous = data.regular.data
  assert previous != nil # All private pair constructors retain complete current versions.
  let roles = previous.privileges.privilegeInfo.value
  if uint64(config.cores) != uint64(roles.cores):
    fail(AccumulationEffectError.InvalidState) # The complete state fixes the profile, not the proposed roster.
  if validators.len < 6 or validators.len mod 3 != 0 or validators.len div 3 > roles.cores:
    fail(AccumulationEffectError.InvalidValidatorCount) # Counts vary within valcount, independently of the initial roster length.
  if uint32(previous.initial.contextInfo.value.service) != uint32(roles.delegator):
    fail(AccumulationEffectError.NotDelegator) # Always use current roles after any bless handoff.
  let encoded = validatorEntry(ValidatorChapter.Staging, validators, config)
  if encoded.error in {StateComponentError.LimitExceeded, StateComponentError.LengthOverflow}:
    fail(AccumulationEffectError.LimitExceeded) # The codec preflights count, typed/native extents and canonical bytes.
  if encoded.error != StateComponentError.None:
    fail(AccumulationEffectError.InvalidState) # No invalid candidate or profile can fabricate a roster.
  let decoded = decodeStateValidators(encoded.value.value, config)
  if decoded.error != StateComponentError.None:
    fail(AccumulationEffectError.InvalidState) # Require one independent canonical typed snapshot before publication.
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([StateWrite(key: encoded.value.key, kind: StateWriteKind.Put,
    value: encoded.value.value)])
  case changed.error
  of StateStoreError.None:
    discard # Both representations share one fully Merklized successor.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Inherited complete-map policy is independent of guest gas.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Prior serialized state and typed roster remain valid.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial candidate escapes other invariant failures.
  let candidate = successorData(previous, changed.value)
  candidate.staging = decoded.value.value
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

proc recordAccumulationNew*(effects: AccumulationEffects, source: AccumulationNewService,
    parameters: Parameters, probes: ServiceProbeLimit): AccumulationEffectResult[
        AccumulationServiceChange] =
  ## Create one service with its empty code request, creator debit and current allocation cursor atomically.
  ## Uses current roles/accounts for authorization/funding, and pinned invocation-start membership for check(i).
  ## Protocol HUH/CASH/FULL refusals are distinct from local malformed state, probe/store limits and backend failure.
  # No partial account, request, cursor or effects owner escapes a refusal.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationServiceChange](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Defaults have no creator or allocation provenance.
  if not parameters.valid:
    fail(AccumulationEffectError.InvalidParameters) # Funding never uses a fabricated deposit schedule.
  let previous = data.regular.data
  assert previous != nil # Private pairs retain complete current contexts.
  let self = previous.initial.contextInfo.value.service
  let roles = previous.privileges.privilegeInfo.value
  if uint64(source.gratis) != 0 and uint32(self) != uint32(roles.manager):
    fail(AccumulationEffectError.NotManager) # Gratuitous storage authority precedes all funding/collision checks.
  let creatorKey = chapterServiceKey(StateChapter(255), self)
  let found = previous.accounts.lookup(creatorKey)
  if found.error != StateStoreError.None or found.value.byteLength != ServiceMetadataBytes:
    fail(AccumulationEffectError.MalformedState) # The actual creator must retain canonical complete metadata.
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    fail(AccumulationEffectError.MalformedState) # Do not repair corrupt source metadata during creation.
  var creator = decoded.value.metadata
  let balance = uint64(creator.balance)
  let gratis = uint64(source.gratis)
  let slot = previous.initial.contextInvocation.value.bootstrapInfo.value.slot
  var child = ServiceMetadata(codeHash: source.codeHash, depositOffset: source.gratis,
    minimumAccumulationGas: source.accumulationGas, minimumTransferGas: source.transferGas,
    storageItems: AccountStorageItems(2), storageBytes: AccountStorageBytes(81'u64+uint64(uint32(
        source.length))),
    created: AccountSlot(uint32(slot)), lastAccumulation: AccountSlot(0),
        parent: self) # E4 length+81 fits uint64.
  var low = 0'u64
  var upper = 0'u64
  if gratis > high(uint64)-balance:
    upper = 1 # Preserve the carry of creator balance plus proposed gratis.
    low = gratis-(high(uint64)-balance)-1
  else:
    low = balance+gratis # This branch proves the two-term addition fits.
  if not consumeAccountDeposit(child, parameters, low, upper):
    fail(AccumulationEffectError.InsufficientCash) # Child's mathematical threshold exceeds all available creator balance.
  let minimum = (if upper != 0 or low >= balance: 0'u64 else: balance-low)
  child.balance = AccountBalance(minimum)
  creator.balance = AccountBalance(balance-minimum) # Exact consumption proves minimum<=balance.
  if not funded(creator, parameters):
    fail(AccumulationEffectError.InsufficientCash) # The debit must also preserve the creator's own threshold.
  var selected = previous.nextService
  var next = previous.nextService
  let desired = uint64(source.desired)
  if uint32(self) == uint32(roles.registrar) and desired < FirstPublicService:
    selected = ServiceIndex(uint32(desired)) # Proven reserved-domain narrowing; no self/low-bit alias is invented.
    let occupied = previous.accounts.lookup(chapterServiceKey(StateChapter(255), selected))
    if occupied.error == StateStoreError.None:
      fail(AccumulationEffectError.ServiceExists) # FULL is only for a registrar's current reserved-ID collision.
    if occupied.error != StateStoreError.MissingKey:
      fail(AccumulationEffectError.InvalidState) # Invalid complete maps cannot fabricate absence.
  else:
    let occupied = previous.accounts.lookup(chapterServiceKey(StateChapter(255), selected))
    if occupied.error != StateStoreError.MissingKey:
      fail(AccumulationEffectError.InvalidState) # An automatic collision cannot overwrite an existing service.
    let advanced = nextAccumulationService(previous.initial.contextAccounts.value, selected, probes)
    if advanced.error == AccumulationInvocationError.LimitExceeded:
      fail(AccumulationEffectError.LimitExceeded) # Probe exhaustion publishes neither child nor cursor advancement.
    if advanced.error != AccumulationInvocationError.None:
      fail(AccumulationEffectError.InvalidState) # Preserve the pinned public-domain/membership invariant.
    next = advanced.value
  let request = serviceRequestEntry(selected, ServicePreimageHash(array[32, byte](source.codeHash)),
    source.length, requestedHistory(), RequestEntryConfig(keyBytes: ByteLimit(32),
      history: RequestHistoryConfig(items: ElementLimit(0), maxBytes: ByteLimit(1))))
  if request.error != RequestError.None:
    fail(AccumulationEffectError.BackendFailure) # Fixed canonical request policy is sufficient; failed derivation never changes namespace.
  let parentEntry = serviceMetadataEntry(self, creator, ByteLimit(ServiceMetadataBytes)).value
  let childEntry = serviceMetadataEntry(selected, child, ByteLimit(ServiceMetadataBytes)).value
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([
    StateWrite(key: parentEntry.key, kind: StateWriteKind.Put, value: parentEntry.value),
    StateWrite(key: childEntry.key, kind: StateWriteKind.Put, value: childEntry.value),
    StateWrite(key: request.value.key, kind: StateWriteKind.Put, value: request.value.value)])
  case changed.error
  of StateStoreError.None:
    discard # All three entries are one fully Merklized successor.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Inherited item/write/byte policies are independent of protocol CASH/FULL.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Source accounts and cursor survive even delayed hash failure.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial candidate escapes other invariant failures.
  let candidate = successorData(previous, changed.value)
  candidate.nextService = next
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationServiceChange](status: AccumulationEffectError.None,
    completed: AccumulationServiceChange(service: selected, effects: AccumulationEffects(data:
    PairData(source: data.source, regular: current, exceptional: data.exceptional))))

proc recordAccumulationUpgrade*(effects: AccumulationEffects, codeHash: CodeHash,
    accumulationGas, transferGas: Gas): AccumulationEffectResult[AccumulationEffects] =
  ## Replace only self's current code hash and minimum gas fields, preserving every other implication and checkpoint.
  ## Inputs are copied nominal values; no offered preimage, privilege or funding condition is required.
  ## Canonical metadata and inherited store policy are checked before one complete successor can escape.
  # Refusals expose neither a partial account map nor an alternative effect version.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # Default effects cannot select a target account.
  let previous = data.regular.data
  assert previous != nil # Private pairs retain complete current versions.
  let self = previous.initial.contextInfo.value.service
  let key = chapterServiceKey(StateChapter(255), self)
  let found = previous.accounts.lookup(key)
  if found.error != StateStoreError.None or found.value.byteLength != ServiceMetadataBytes:
    fail(AccumulationEffectError.MalformedState) # Never fabricate or repair the actual caller's metadata.
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    fail(AccumulationEffectError.MalformedState) # Only canonical complete metadata may be changed.
  var metadata = decoded.value.metadata
  metadata.codeHash = codeHash
  metadata.minimumAccumulationGas = accumulationGas
  metadata.minimumTransferGas = transferGas
  let encoded = serviceMetadataEntry(self, metadata, ByteLimit(ServiceMetadataBytes)).value
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([StateWrite(key: key, kind: StateWriteKind.Put,
      value: encoded.value)])
  case changed.error
  of StateStoreError.None:
    discard # All three fields share one fully Merklized metadata replacement.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Local policy cannot fabricate a guest resource code.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Existing accounts and every retained owner survive hashing refusal.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial candidate escapes other invariant failures.
  let candidate = successorData(previous, changed.value)
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))

proc effectTransferAt*(context: AccumulationEffectContext, index: AccumulationTransferIndex):
    AccumulationEffectResult[DeferredTransfer] =
  ## Copy one complete outgoing transfer by its ordinal; no mutable memo or backing sequence escapes.
  let data = context.data
  if data == nil:
    return AccumulationEffectResult[DeferredTransfer](
        status: AccumulationEffectError.Uninitialized) # Defaults own no transfers.
  if uint64(index) >= uint64(data.transfers.values.len):
    return AccumulationEffectResult[DeferredTransfer](
        status: AccumulationEffectError.InvalidIndex) # Bound before native narrowing.
  AccumulationEffectResult[DeferredTransfer](status: AccumulationEffectError.None,
    completed: data.transfers.values[int(uint64(index))])

proc prepareAccumulationTransfer*(effects: AccumulationEffects,
    destination: AccumulationTransferDestination,

amount: TransferBalance, gas: Gas, memo: TransferMemo, parameters: Parameters):
    AccumulationEffectResult[PreparedAccumulationTransfer] =
  ## Validate WHO/LOW/CASH in pinned order without writes/hashing; the immutable plan binds this exact source version.
  ## Gas charging and append/store capacity belong after this pure validation; inputs are copied fixed values.
  # Failed plans expose no metadata, memo or source owner payload.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[PreparedAccumulationTransfer](status: reason)
  let data = effects.data
  if data == nil:
    fail(AccumulationEffectError.Uninitialized) # No default owner can authorize a debit.
  if not parameters.valid:
    fail(AccumulationEffectError.InvalidParameters) # Funding never uses a fabricated schedule.
  let previous = data.regular.data
  assert previous != nil # Private constructors retain complete current snapshots.
  if uint64(destination) > uint64(high(uint32)):
    fail(AccumulationEffectError.UnknownService) # Full-width destination has no sentinel or low-bit alias.
  let target = ServiceIndex(uint32(uint64(destination)))
  let found = previous.accounts.lookup(chapterServiceKey(StateChapter(255), target))
  if found.error == StateStoreError.MissingKey:
    fail(AccumulationEffectError.UnknownService) # Actual current membership alone authorizes destination lookup.
  if found.error != StateStoreError.None or found.value.byteLength != ServiceMetadataBytes:
    fail(AccumulationEffectError.MalformedState) # Corrupt current targets are not fabricated absent accounts.
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    fail(AccumulationEffectError.MalformedState) # Require canonical target metadata before minimum-gas comparison.
  if uint64(gas) < uint64(decoded.value.metadata.minimumTransferGas):
    fail(AccumulationEffectError.TransferGasLow) # LOW precedes creator funding checks.
  let self = previous.initial.contextInfo.value.service
  let creator = previous.accounts.lookup(chapterServiceKey(StateChapter(255), self))
  if creator.error != StateStoreError.None or creator.value.byteLength != ServiceMetadataBytes:
    fail(AccumulationEffectError.MalformedState) # The invoking account must remain complete and canonical.
  let original = decodeServiceMetadata(creator.value.bytes, ByteLimit(ServiceMetadataBytes))
  if original.error != ServiceMetadataError.None:
    fail(AccumulationEffectError.MalformedState) # Never repair source metadata while transferring funds.
  var metadata = original.value.metadata
  if uint64(amount) > uint64(metadata.balance):
    fail(AccumulationEffectError.InsufficientCash) # Prove subtraction before computing the prospective debit.
  metadata.balance = AccountBalance(uint64(metadata.balance)-uint64(amount))
  if not funded(metadata, parameters):
    fail(AccumulationEffectError.InsufficientCash) # CASH includes the creator's own exact storage threshold.
  let plan = PreparedAccumulationTransfer(data: TransferPlanData(source: effects,
    metadata: metadata,
    transfer: DeferredTransfer(source: self, destination: target, amount: amount, gas: gas, memo: memo)))
  AccumulationEffectResult[PreparedAccumulationTransfer](status: AccumulationEffectError.None,
      completed: plan)

proc commitAccumulationTransfer*(prepared: PreparedAccumulationTransfer, limit: ElementLimit):
    AccumulationEffectResult[AccumulationEffects] =
  ## Publish the bound creator debit and one ordered append atomically; callers must first charge conditional host gas.
  ## Reusing a plan produces successors of the same retained version, never appends to an ambient replacement state.
  # No partially debited account or detached transfer sequence escapes any refusal.
  template fail(reason: AccumulationEffectError) =
    return AccumulationEffectResult[AccumulationEffects](status: reason)
  let plan = prepared.data
  if plan == nil:
    fail(AccumulationEffectError.Uninitialized) # A default handle grants no prepared transfer.
  let data = plan.source.data
  assert data != nil # Only successful preparation creates a source-bound plan.
  let previous = data.regular.data
  assert previous != nil # Prepared immutable pairs always retain their current child.
  let count = previous.transfers.values.len
  if uint64(count) >= uint64(limit) or count >= high(int) div sizeof(DeferredTransfer):
    fail(AccumulationEffectError.LimitExceeded) # Prove count+1 and typed allocation extent before appending.
  var transfers = newSeq[DeferredTransfer](count+1)
  for i in 0..<count:
    transfers[i] = previous.transfers.values[i] # Copy fixed values in exact existing order, including duplicates.
  transfers[count] = plan.transfer
  let encoded = serviceMetadataEntry(plan.transfer.source, plan.metadata, ByteLimit(
      ServiceMetadataBytes)).value
  var working = forkStateStore(previous.accounts).value
  let changed = working.apply([StateWrite(key: encoded.key, kind: StateWriteKind.Put,
      value: encoded.value)])
  case changed.error
  of StateStoreError.None:
    discard # Only a fully Merklized creator debit can accompany the appended transfer.
  of StateStoreError.LimitExceeded:
    fail(AccumulationEffectError.LimitExceeded) # Inherited store policy remains an explicit local refusal.
  of StateStoreError.BackendFailure:
    fail(AccumulationEffectError.BackendFailure) # Old accounts and outgoing owners survive hashing failure.
  else:
    fail(AccumulationEffectError.InvalidState) # No partial candidate escapes other invariant failures.
  let candidate = successorData(previous, changed.value)
  candidate.transfers = TransferSetData(values: transfers)
  let current = AccumulationEffectContext(data: candidate)
  AccumulationEffectResult[AccumulationEffects](status: AccumulationEffectError.None,
    completed: AccumulationEffects(data: PairData(source: data.source, regular: current,
      exceptional: data.exceptional)))
