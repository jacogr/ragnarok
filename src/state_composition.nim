## GP 0.8.0 T composition under the recorded, unresolved C12/C13 width interpretation.
## Chapter snapshots are exact typed captures; this does not validate transitions or settle parity gates.
import ./[bounded, assurances, guarantees, state_layout, state_trie, state_authorization,
  state_history,
  state_consensus, state_disputes, state_safrole, state_availability, state_privileges,
  state_statistics, state_workqueues, state_outputs, state_accounts, state_service_values,
  state_requests]

type
  ## Total enum makes each of the sixteen required chapter slots explicit at the composition boundary.
  StateChapterId* {.pure.} = enum
    Pools = 1, Queues, History, Safrole, Disputes, Entropy, Staging, Active, Previous,
    Availability, Time, Privileges, Statistics, Ready, Accumulated, Outputs
  ## Shared chain cardinalities bind captures to one interpretation; limits are separate caller policy.
  StateProfile* = object
    cores*: CoreCount
    current*, previous*: ValidatorCount
    epochSlots*: EpochSlots
  ## Common conservative item/byte ceilings feed existing chapter-specific checked decoders.
  StateChapterPolicy* = object
    items*: ElementLimit
    maxBytes*: ByteLimit
  ## Failed/default results contain only a reason, never a root, owner, entry or progress.
  StateCompositionError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidComponent, Truncated, NonCanonical, TrailingBytes,
    LimitExceeded, LengthOverflow, DuplicateKey, BackendFailure, InvalidOwner, InvalidIndex,
    WrongChapter, ProfileMismatch
  ## Only complete success exposes the selected result value.
  StateCompositionResult*[T] = object
    case error*: StateCompositionError
    of StateCompositionError.None:
      value*: T # Checked variant access requires successful selection.
    else:
      discard   # No partially composed mapping escapes on any failure.
  ## Private acyclic owner retains exact bytes after typed decoding; no borrowed spans escape.
  StateChapterData = ref object
    chapter: StateChapterId
    profile: StateProfile
    bytes: seq[byte]
  ## Immutable handle cannot be forged with raw bytes or edited through public fields.
  StateChapterSnapshot* = object
    data: StateChapterData
  ## One raw storage source; stable input is borrowed only during synchronous composition.
  StateStorageItem* = object
    key*, value*: seq[byte]
  ## Opaque preimage content is preserved without asserting its hash/content validity.
  StatePreimageItem* = object
    hash*: ServicePreimageHash
    value*: seq[byte]
  ## Request identity and fixed tagged history retain their existing complete E4 domains.
  StateRequestItem* = object
    hash*: ServicePreimageHash
    length*: RequestLength
    history*: RequestHistory
  ## Metadata plus nested service mappings; captured values support storage without original keys.
  StateService* = object
    service*: ServiceIndex
    metadata*: ServiceMetadata
    storage*: seq[StateStorageItem]
    preimages*: seq[StatePreimageItem]
    requests*: seq[StateRequestItem]
    captured*: seq[ServiceValueSnapshot]
  ## Entry extraction takes an ordinal, never a service index, chapter number or byte offset.
  StateEntryIndex* = distinct uint64
  ## Private final mapping owns all value bytes; no source pointers or mutable arrays are exported.
  StateCompositionData = ref object
    entries: seq[StateEntry]
    commitment: StateTrieCommitment
  ## Immutable completed state mapping, explicitly not a valid-state or execution certificate.
  StateSnapshot* = object
    data: StateCompositionData

## Reject unsupported shared profiles before any decoder traverses caller input.
proc valid(profile: StateProfile): bool =
  validConfig(AssuranceConfig(cores: profile.cores, validators: profile.current)) and
    validConfig(AssuranceConfig(cores: profile.cores, validators: profile.previous)) and
    uint64(profile.epochSlots) > 0

## Captures may use different resource ceilings, but must describe identical chain cardinalities.
proc same(a, b: StateProfile): bool =
  uint64(a.cores) == uint64(b.cores) and uint64(a.current) == uint64(b.current) and
    uint64(a.previous) == uint64(b.previous) and uint64(a.epochSlots) == uint64(b.epochSlots)

## Preserve shared typed failure reasons; child-specific schema failures remain InvalidComponent.
proc reason[T: enum](error: T): StateCompositionError =
  # Only reasons defined in this child's nominal enum participate in the corresponding comparison.
  when compiles(T.LimitExceeded):
    if error == T.LimitExceeded: return StateCompositionError.LimitExceeded # Caller policy remains distinguishable.
  when compiles(T.LengthOverflow):
    if error == T.LengthOverflow: return StateCompositionError.LengthOverflow # Never narrow an oversized extent.
  when compiles(T.BackendFailure):
    if error == T.BackendFailure: return StateCompositionError.BackendFailure # No fabricated crypto result.
  when compiles(T.Truncated):
    if error == T.Truncated: return StateCompositionError.Truncated # Preserve missing child bytes.
  when compiles(T.NonCanonical):
    if error == T.NonCanonical: return StateCompositionError.NonCanonical # Preserve noncanonical child framing.
  when compiles(T.DuplicateKey):
    if error == T.DuplicateKey: return StateCompositionError.DuplicateKey # No implicit map overwrite.
  StateCompositionError.InvalidComponent

## Decode the selected typed component and require exact extent before retaining an independent copy.
## Input is stable only during this call. Temporary typed child owners are released by ARC.
proc captureStateChapter*(chapter: StateChapterId, input: openArray[byte], profile: StateProfile,
    policy: StateChapterPolicy): StateCompositionResult[StateChapterSnapshot] =
  if not valid(profile):
    return StateCompositionResult[StateChapterSnapshot](
        error: StateCompositionError.InvalidConfig) # Reject profile before input.
  if uint64(input.len) > uint64(policy.maxBytes):
    return StateCompositionResult[StateChapterSnapshot](
        error: StateCompositionError.LimitExceeded) # Bound even a valid shorter prefix.
  let roster = ValidatorStateConfig(cores: profile.cores, validators: policy.items,
      maxBytes: policy.maxBytes)
  let queues = WorkQueueConfig(cores: profile.cores, epochSlots: profile.epochSlots,
    perSlot: policy.items, totalItems: policy.items, perDependencies: policy.items,
    totalDependencies: policy.items, reportBytes: policy.maxBytes, maxBytes: policy.maxBytes)
  var consumed: int
  ## Each typed decoder must succeed before its consumed extent is accessible.
  template read(expression: untyped) =
    block:
      let decoded = expression
      if decoded.error != typeof(decoded.error).None:
        return StateCompositionResult[StateChapterSnapshot](error: reason(
            decoded.error)) # Failed children expose no data.
      consumed = decoded.value.consumed
  # Dispatch by explicit chapter identity; no byte-content guessing or alternate-width fallback is allowed.
  case chapter
  of StateChapterId.Pools, StateChapterId.Queues:
    read(decodeAuthorization((if chapter == StateChapterId.Pools: AuthorizationKind.Pools else: AuthorizationKind.Queues),
        input, AuthorizationConfig(cores: profile.cores, maxHashes: policy.items,
        maxBytes: policy.maxBytes))) # Ordered core pools or fixed queues retain their distinct framing.
  of StateChapterId.History:
    read(decodeHistoryState(input, HistoryConfig(cores: profile.cores, blocks: policy.items,
        perBlock: policy.items, totalPackages: policy.items, peaks: policy.items,
        maxBytes: policy.maxBytes))) # History tuples and optional belt peaks follow the existing chapter-3 schema.
  of StateChapterId.Safrole:
    read(decodeSafroleState(input, SafroleStateConfig(validators: roster,
        epochSlots: profile.epochSlots, maxAccumulator: policy.items,
        maxBytes: policy.maxBytes))) # Pending rosters, sealer variants and tickets retain the existing epoch policy.
  of StateChapterId.Disputes:
    read(decodeDisputeState(input, DisputeStateConfig(perSet: policy.items,
        totalItems: policy.items,
        maxBytes: policy.maxBytes))) # Canonical judgment/offender sets must decode completely.
  of StateChapterId.Entropy:
    read(decodeStateEntropy(input)) # Entropy retains all four fixed words without a count prefix.
  of StateChapterId.Staging, StateChapterId.Active, StateChapterId.Previous:
    read(decodeStateValidators(input, roster)) # Each ordered roster uses its existing bounded population rules.
  of StateChapterId.Availability:
    read(decodeAvailabilityState(input, AvailabilityConfig(guarantee: GuaranteeConfig(
        cores: profile.cores, validators: profile.current, maxBytes: policy.maxBytes),
        maxPresent: policy.items,
        maxBytes: policy.maxBytes))) # Full optional guarantees use the shared core/current-validator profile.
  of StateChapterId.Time:
    read(decodeStateTime(input)) # Timeslots remain exact E4 values.
  of StateChapterId.Privileges:
    read(decodePrivilegeState(input, PrivilegeConfig(cores: profile.cores, maxAlways: policy.items,
        maxBytes: policy.maxBytes))) # The recorded privilege width interpretation remains explicit and unchanged.
  of StateChapterId.Statistics:
    read(decodeActivityState(input, ActivityConfig(cores: profile.cores, current: profile.current,
        previous: profile.previous, maxServices: policy.items,
        maxBytes: policy.maxBytes))) # The recorded statistics width interpretation remains explicit and unchanged.
  of StateChapterId.Ready:
    read(decodeReadyState(input, queues)) # Ready rows retain full report/dependency validation.
  of StateChapterId.Accumulated:
    read(decodeAccumulatedState(input, queues)) # Accumulated rows retain canonical hash-set validation.
  of StateChapterId.Outputs:
    read(decodeOutputLog(input, OutputLogConfig(items: policy.items,
        maxBytes: policy.maxBytes))) # The last-output sequence retains E4 service identities and ordered commitments.
  if consumed != input.len:
    return StateCompositionResult[StateChapterSnapshot](
        error: StateCompositionError.TrailingBytes) # Prefix success is not a complete state entry.
  let data = StateChapterData(chapter: chapter, profile: profile, bytes: @input)
  StateCompositionResult[StateChapterSnapshot](error: StateCompositionError.None,
    value: StateChapterSnapshot(data: data))

## Charge one complete entry without overflow before output allocation or key hashing.
proc charge(size: uint64, limits: StateTrieLimits, count,
    total: var uint64): StateCompositionError =
  if count >= uint64(limits.items) or count >= uint64(high(int) div sizeof(StateEntry)):
    return StateCompositionError.LimitExceeded # Bound descriptor work before incrementing.
  if size > uint64(limits.perValue) or size > uint64(limits.totalValueBytes)-total:
    return StateCompositionError.LimitExceeded # Subtraction guards aggregate addition, including uint64 maxima.
  inc count
  total += size
  StateCompositionError.None

## Count encoded request bytes without allocating, hashing or weakening the existing four-shape union.
proc historySize(history: RequestHistory): uint64 =
  1'u64+4'u64*uint64(ord(history.state))

## Compose all required exact chapters plus typed service entries under one profile and parent policy.
## Sources remain stable for this synchronous call. Parent failure publishes no partial mapping/root.
## Duplicate identities, including namespace overlaps, reject rather than choosing an overwrite policy.
proc composeState*(chapters: array[StateChapterId, StateChapterSnapshot],
    services: openArray[StateService], limits: StateTrieLimits,
    maxStorageKeyBytes: ByteLimit): StateCompositionResult[StateSnapshot] =
  var count, total: uint64
  ## Apply the same complete parent budget to chapters and every nested service entry.
  template account(size: untyped) =
    block:
      let error = charge(uint64(size), limits, count, total)
      if error != StateCompositionError.None:
        return StateCompositionResult[StateSnapshot](error: error) # No partial owner is published.
  # Inspect private captures before copying any payload or allocating the final mapping.
  for chapter in StateChapterId:
    let part = chapters[chapter].data
    if part.isNil:
      return StateCompositionResult[StateSnapshot](
          error: StateCompositionError.InvalidOwner) # Missing chapters cannot imply zero/default values.
    if part.chapter != chapter:
      return StateCompositionResult[StateSnapshot](
          error: StateCompositionError.WrongChapter) # A valid component cannot be relabeled.
    if not same(part.profile, chapters[StateChapterId.Pools].data.profile):
      return StateCompositionResult[StateSnapshot](
          error: StateCompositionError.ProfileMismatch) # No mixing cardinality domains.
    account(part.bytes.len)
  # Traverse every nested descriptor before any service-key hashing or output-value copying.
  for service in services:
    account(ServiceMetadataBytes)
    for item in service.storage:
      if uint64(item.key.len) > uint64(maxStorageKeyBytes):
        return StateCompositionResult[StateSnapshot](
            error: StateCompositionError.LimitExceeded) # Raw key work has independent policy.
      account(item.value.len)
    for item in service.preimages:
      account(item.value.len) # Raw values have no count/length framing.
    for item in service.requests:
      account(historySize(item.history)) # Every tagged history has an exact fixed encoded extent.
    for item in service.captured:
      let info = serviceValueInfo(item)
      if info.error != ServiceValueError.None:
        return StateCompositionResult[StateSnapshot](
            error: StateCompositionError.InvalidOwner) # Default opaque handles cannot supply entries.
      if uint32(info.value.service) != uint32(service.service):
        return StateCompositionResult[StateSnapshot](
            error: StateCompositionError.InvalidComponent) # An opaque entry stays bound to its original service.
      account(info.value.length)
  var entries = newSeqOfCap[StateEntry](int(count))
  # Immutable chapter bytes can be retained safely; public extraction always returns independent copies.
  for chapter in StateChapterId:
    entries.add(StateEntry(key: chapterKey(StateChapter(ord(chapter))), value: chapters[
        chapter].data.bytes))
  ## Existing entry encoders construct independent values and preserve nominal key/hash/history contracts.
  template append(expression: untyped) =
    block:
      let encoded = expression
      if encoded.error != typeof(encoded.error).None:
        return StateCompositionResult[StateSnapshot](error: reason(
            encoded.error)) # A failed key/child contributes no entry.
      entries.add(encoded.value)
  # Preserve source traversal order; the trie sorts private key indices and rejects all duplicates.
  for service in services:
    append(serviceMetadataEntry(service.service, service.metadata, limits.perValue))
    for item in service.storage:
      append(serviceStorageEntry(service.service, item.key, item.value,
        ServiceEntryLimits(keyBytes: maxStorageKeyBytes, valueBytes: limits.perValue)))
    for item in service.preimages:
      append(servicePreimageEntry(service.service, item.hash, item.value,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: limits.perValue)))
    for item in service.requests:
      append(serviceRequestEntry(service.service, item.hash, item.length, item.history,
        RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
            items: ElementLimit(3), maxBytes: limits.perValue))))
    for item in service.captured:
      append(serviceValueEntry(item, limits.perValue)) # Previously captured raw values retain their exact existing key.
  let committed = stateTrieRoot(entries, limits)
  if committed.error != StateTrieError.None:
    return StateCompositionResult[StateSnapshot](error: reason(
        committed.error)) # Duplicates/topology/backend failures expose no root.
  StateCompositionResult[StateSnapshot](error: StateCompositionError.None,
    value: StateSnapshot(data: StateCompositionData(entries: entries, commitment: committed.value)))

## Return a copied fixed commitment only from a complete immutable owner.
proc stateCommitment*(owner: StateSnapshot): StateCompositionResult[StateTrieCommitment] =
  if owner.data.isNil:
    return StateCompositionResult[StateTrieCommitment](
        error: StateCompositionError.InvalidOwner) # No default state root.
  StateCompositionResult[StateTrieCommitment](error: StateCompositionError.None,
      value: owner.data.commitment)

## Copy one complete entry into independent caller-owned storage after nominal index validation.
proc stateEntryAt*(owner: StateSnapshot, index: StateEntryIndex): StateCompositionResult[StateEntry] =
  if owner.data.isNil:
    return StateCompositionResult[StateEntry](error: StateCompositionError.InvalidOwner) # Missing owner cannot authorize extraction.
  if uint64(index) >= uint64(owner.data.entries.len):
    return StateCompositionResult[StateEntry](error: StateCompositionError.InvalidIndex) # Validate before narrowing.
  let entry = owner.data.entries[int(uint64(index))]
  var copy = StateEntry(key: entry.key, value: newSeq[byte](entry.value.len))
  # No exported mutable sequence aliases private chapter or composed-state storage.
  for i in 0..<copy.value.len: copy.value[i] = entry.value[i]
  StateCompositionResult[StateEntry](error: StateCompositionError.None, value: copy)
