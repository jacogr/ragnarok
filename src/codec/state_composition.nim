# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 T composition with migrated dictionary widths; C13 gas follows the vector-compatible compact policy.
## Chapter snapshots are exact typed captures; this does not validate transitions or settle parity gates.
import std/assertions
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
    case status: StateCompositionError
    of None:
      completed: T # Complete payload access requires the guarded accessor.
    else:
      discard      # No partially composed mapping escapes on any failure.
  ## Private acyclic owner retains exact bytes after typed decoding; no borrowed spans escape.
  StateChapterData = ref object
    chapter: StateChapterId
    profile: StateProfile
    bytes: seq[byte]
  ## Immutable handle cannot be forged with raw bytes or edited through public fields.
  StateChapterSnapshot* = object
    data: nil StateChapterData
  ## Fixed complete chapter slots retain nominal chapter indexing without nonzero enum-indexed array defaults.
  StateChapters* = object
    slots: array[16, StateChapterSnapshot]
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
    data: nil StateCompositionData

## Failure reasons are read-only and cannot authorize chapter bytes, whole mappings or roots.
func error*[T](value: StateCompositionResult[T]): StateCompositionError = value.status
## Complete public payloads require successful selection before any retained data is exposed.
func value*[T](value: StateCompositionResult[T]): T
    {.inline, requires: value.status == StateCompositionError.None.} = value.completed

## Select one retained chapter handle through its nominal identity; default slots remain missing owners.
func `[]`*(chapters: StateChapters, chapter: StateChapterId): StateChapterSnapshot
    {.inline, requires: ord(chapter) >= 1 and ord(chapter) <= 16.} = chapters.slots[ord(chapter)-1]
## Replace a caller-owned chapter slot without exposing the immutable capture's private bytes.
proc `[]=`*(chapters: var StateChapters, chapter: StateChapterId, value: StateChapterSnapshot)
    {.inline, requires: ord(chapter) >= 1 and ord(chapter) <= 16.} = chapters.slots[ord(
        chapter)-1] = value

## Reject unsupported shared profiles before any decoder traverses caller input.
proc valid(profile: StateProfile): bool =
  validConfig(AssuranceConfig(cores: profile.cores, validators: profile.current)) and
    validConfig(AssuranceConfig(cores: profile.cores, validators: profile.previous)) and
    uint64(profile.epochSlots) > 0

## Captures may use different resource ceilings, but must describe identical chain cardinalities.
proc same(a, b: StateProfile): bool =
  uint64(a.cores) == uint64(b.cores) and uint64(a.current) == uint64(b.current) and
    uint64(a.previous) == uint64(b.previous) and uint64(a.epochSlots) == uint64(b.epochSlots)

## Preserve shared AuthorizationError failures explicitly; remaining child schema errors invalidate this component.
proc reason(error: AuthorizationError): StateCompositionError =
  case error
  of AuthorizationError.LimitExceeded: StateCompositionError.LimitExceeded # Retain the child failure category.
  of AuthorizationError.LengthOverflow: StateCompositionError.LengthOverflow # Retain the child failure category.
  of AuthorizationError.Truncated: StateCompositionError.Truncated # Retain the child failure category.
  of AuthorizationError.NonCanonical: StateCompositionError.NonCanonical # Retain the child failure category.
  else: StateCompositionError.InvalidComponent # No unrecognized child status can authorize a component.

## Preserve shared HistoryError failures explicitly; remaining child schema errors invalidate this component.
proc reason(error: HistoryError): StateCompositionError =
  case error
  of HistoryError.LimitExceeded: StateCompositionError.LimitExceeded # Retain the child failure category.
  of HistoryError.LengthOverflow: StateCompositionError.LengthOverflow # Retain the child failure category.
  of HistoryError.Truncated: StateCompositionError.Truncated # Retain the child failure category.
  of HistoryError.NonCanonical: StateCompositionError.NonCanonical # Retain the child failure category.
  else: StateCompositionError.InvalidComponent # No unrecognized child status can authorize a component.

## Preserve shared StateComponentError failures explicitly; remaining child schema errors invalidate this component.
proc reason(error: StateComponentError): StateCompositionError =
  case error
  of StateComponentError.LimitExceeded: StateCompositionError.LimitExceeded # Retain the child failure category.
  of StateComponentError.LengthOverflow: StateCompositionError.LengthOverflow # Retain the child failure category.
  of StateComponentError.Truncated: StateCompositionError.Truncated # Retain the child failure category.
  of StateComponentError.NonCanonical: StateCompositionError.NonCanonical # Retain the child failure category.
  else: StateCompositionError.InvalidComponent # No unrecognized child status can authorize a component.

## Preserve shared DisputeStateError failures explicitly; remaining child schema errors invalidate this component.
proc reason(error: DisputeStateError): StateCompositionError =
  case error
  of DisputeStateError.LimitExceeded: StateCompositionError.LimitExceeded # Retain the child failure category.
  of DisputeStateError.LengthOverflow: StateCompositionError.LengthOverflow # Retain the child failure category.
  of DisputeStateError.Truncated: StateCompositionError.Truncated # Retain the child failure category.
  of DisputeStateError.NonCanonical: StateCompositionError.NonCanonical # Retain the child failure category.
  else: StateCompositionError.InvalidComponent # No unrecognized child status can authorize a component.

## Preserve shared AvailabilityError failures explicitly; remaining child schema errors invalidate this component.
proc reason(error: AvailabilityError): StateCompositionError =
  case error
  of AvailabilityError.LimitExceeded: StateCompositionError.LimitExceeded # Retain the child failure category.
  of AvailabilityError.LengthOverflow: StateCompositionError.LengthOverflow # Retain the child failure category.
  of AvailabilityError.Truncated: StateCompositionError.Truncated # Retain the child failure category.
  of AvailabilityError.NonCanonical: StateCompositionError.NonCanonical # Retain the child failure category.
  else: StateCompositionError.InvalidComponent # No unrecognized child status can authorize a component.

## Preserve shared PrivilegeError failures explicitly; remaining child schema errors invalidate this component.
proc reason(error: PrivilegeError): StateCompositionError =
  case error
  of PrivilegeError.LimitExceeded: StateCompositionError.LimitExceeded # Retain the child failure category.
  of PrivilegeError.LengthOverflow: StateCompositionError.LengthOverflow # Retain the child failure category.
  of PrivilegeError.Truncated: StateCompositionError.Truncated # Retain the child failure category.
  of PrivilegeError.NonCanonical: StateCompositionError.NonCanonical # Retain the child failure category.
  else: StateCompositionError.InvalidComponent # No unrecognized child status can authorize a component.

## Preserve shared ActivityError failures explicitly; remaining child schema errors invalidate this component.
proc reason(error: ActivityError): StateCompositionError =
  case error
  of ActivityError.LimitExceeded: StateCompositionError.LimitExceeded # Retain the child failure category.
  of ActivityError.LengthOverflow: StateCompositionError.LengthOverflow # Retain the child failure category.
  of ActivityError.Truncated: StateCompositionError.Truncated # Retain the child failure category.
  of ActivityError.NonCanonical: StateCompositionError.NonCanonical # Retain the child failure category.
  else: StateCompositionError.InvalidComponent # No unrecognized child status can authorize a component.

## Preserve shared WorkQueueError failures explicitly; remaining child schema errors invalidate this component.
proc reason(error: WorkQueueError): StateCompositionError =
  case error
  of WorkQueueError.LimitExceeded: StateCompositionError.LimitExceeded # Retain the child failure category.
  of WorkQueueError.LengthOverflow: StateCompositionError.LengthOverflow # Retain the child failure category.
  of WorkQueueError.Truncated: StateCompositionError.Truncated # Retain the child failure category.
  of WorkQueueError.NonCanonical: StateCompositionError.NonCanonical # Retain the child failure category.
  else: StateCompositionError.InvalidComponent # No unrecognized child status can authorize a component.

## Preserve shared OutputLogError failures explicitly; remaining child schema errors invalidate this component.
proc reason(error: OutputLogError): StateCompositionError =
  case error
  of OutputLogError.LimitExceeded: StateCompositionError.LimitExceeded # Retain the child failure category.
  of OutputLogError.LengthOverflow: StateCompositionError.LengthOverflow # Retain the child failure category.
  of OutputLogError.Truncated: StateCompositionError.Truncated # Retain the child failure category.
  of OutputLogError.NonCanonical: StateCompositionError.NonCanonical # Retain the child failure category.
  else: StateCompositionError.InvalidComponent # No unrecognized child status can authorize a component.

## Preserve shared StateTrieError failures explicitly; remaining child schema errors invalidate this component.
proc reason(error: StateTrieError): StateCompositionError =
  case error
  of StateTrieError.LimitExceeded: StateCompositionError.LimitExceeded # Retain the child failure category.
  of StateTrieError.LengthOverflow: StateCompositionError.LengthOverflow # Retain the child failure category.
  of StateTrieError.BackendFailure: StateCompositionError.BackendFailure # Retain the child failure category.
  of StateTrieError.DuplicateKey: StateCompositionError.DuplicateKey # Retain the child failure category.
  else: StateCompositionError.InvalidComponent # No unrecognized child status can authorize a component.

## Preserve shared ServiceMetadataError failures explicitly; remaining child schema errors invalidate this component.
proc reason(error: ServiceMetadataError): StateCompositionError =
  case error
  of ServiceMetadataError.LimitExceeded: StateCompositionError.LimitExceeded # Retain the child failure category.
  of ServiceMetadataError.Truncated: StateCompositionError.Truncated # Retain the child failure category.
  of ServiceMetadataError.NonCanonical: StateCompositionError.NonCanonical # Retain the child failure category.
  else: StateCompositionError.InvalidComponent # No unrecognized child status can authorize a component.

## Preserve shared ServiceValueError failures explicitly; remaining child schema errors invalidate this component.
proc reason(error: ServiceValueError): StateCompositionError =
  case error
  of ServiceValueError.LimitExceeded: StateCompositionError.LimitExceeded # Retain the child failure category.
  of ServiceValueError.LengthOverflow: StateCompositionError.LengthOverflow # Retain the child failure category.
  of ServiceValueError.BackendFailure: StateCompositionError.BackendFailure # Retain the child failure category.
  else: StateCompositionError.InvalidComponent # No unrecognized child status can authorize a component.

## Preserve shared RequestError failures explicitly; remaining child schema errors invalidate this component.
proc reason(error: RequestError): StateCompositionError =
  case error
  of RequestError.LimitExceeded: StateCompositionError.LimitExceeded # Retain the child failure category.
  of RequestError.Truncated: StateCompositionError.Truncated # Retain the child failure category.
  of RequestError.NonCanonical: StateCompositionError.NonCanonical # Retain the child failure category.
  of RequestError.BackendFailure: StateCompositionError.BackendFailure # Retain the child failure category.
  else: StateCompositionError.InvalidComponent # No unrecognized child status can authorize a component.

## Decode the selected typed component and require exact extent before retaining an independent copy.
## Input is stable only during this call. Temporary typed child owners are released by ARC.
proc captureStateChapter*(chapter: StateChapterId, input: openArray[byte], profile: StateProfile,
    policy: StateChapterPolicy): StateCompositionResult[StateChapterSnapshot] =
  if not valid(profile):
    return StateCompositionResult[StateChapterSnapshot](
        status: StateCompositionError.InvalidConfig) # Reject profile before input.
  if uint64(input.len) > uint64(policy.maxBytes):
    return StateCompositionResult[StateChapterSnapshot](
        status: StateCompositionError.LimitExceeded) # Bound even a valid shorter prefix.
  if ord(chapter) < 1 or ord(chapter) > 16:
    return StateCompositionResult[StateChapterSnapshot](
        status: StateCompositionError.InvalidComponent) # A forged enum cannot select an unvalidated component.
  let roster = ValidatorStateConfig(cores: profile.cores, validators: policy.items,
      maxBytes: policy.maxBytes)
  let queues = WorkQueueConfig(cores: profile.cores, epochSlots: profile.epochSlots,
    perSlot: policy.items, totalItems: policy.items, perDependencies: policy.items,
    totalDependencies: policy.items, reportBytes: policy.maxBytes, maxBytes: policy.maxBytes)
  var consumed = 0
  # Dispatch by explicit chapter identity; no byte-content guessing or alternate-width fallback is allowed.
  case chapter
  of StateChapterId.Pools, StateChapterId.Queues:
    let decoded = decodeAuthorization((if chapter ==
        StateChapterId.Pools: AuthorizationKind.Pools else: AuthorizationKind.Queues), input,
        AuthorizationConfig(cores: profile.cores,
        maxHashes: policy.items,
        maxBytes: policy.maxBytes))
    if decoded.error != AuthorizationError.None:
      return StateCompositionResult[StateChapterSnapshot](status: reason(
          decoded.error)) # Child failure publishes no data.
    consumed = decoded.value.consumed # Ordered core pools or fixed queues retain their distinct framing.
  of StateChapterId.History:
    let decoded = decodeHistoryState(input, HistoryConfig(cores: profile.cores,
        blocks: policy.items, perBlock: policy.items, totalPackages: policy.items,
        peaks: policy.items,
        maxBytes: policy.maxBytes))
    if decoded.error != HistoryError.None:
      return StateCompositionResult[StateChapterSnapshot](status: reason(
          decoded.error)) # Child failure publishes no data.
    consumed = decoded.value.consumed # History tuples and optional belt peaks follow the existing chapter-3 schema.
  of StateChapterId.Safrole:
    let decoded = decodeSafroleState(input, SafroleStateConfig(validators: roster,
        epochSlots: profile.epochSlots, maxAccumulator: policy.items,
        maxBytes: policy.maxBytes))
    if decoded.error != StateComponentError.None:
      return StateCompositionResult[StateChapterSnapshot](status: reason(
          decoded.error)) # Child failure publishes no data.
    consumed = decoded.value.consumed # Pending rosters, sealer variants and tickets retain the existing epoch policy.
  of StateChapterId.Disputes:
    let decoded = decodeDisputeState(input, DisputeStateConfig(perSet: policy.items,
        totalItems: policy.items,
        maxBytes: policy.maxBytes))
    if decoded.error != DisputeStateError.None:
      return StateCompositionResult[StateChapterSnapshot](status: reason(
          decoded.error)) # Child failure publishes no data.
    consumed = decoded.value.consumed # Canonical judgment/offender sets must decode completely.
  of StateChapterId.Entropy:
    let decoded = decodeStateEntropy(input)
    if decoded.error != StateComponentError.None:
      return StateCompositionResult[StateChapterSnapshot](status: reason(
          decoded.error)) # Child failure publishes no data.
    consumed = decoded.value.consumed # Entropy retains all four fixed words without a count prefix.
  of StateChapterId.Staging, StateChapterId.Active, StateChapterId.Previous:
    let decoded = decodeStateValidators(input, roster)
    if decoded.error != StateComponentError.None:
      return StateCompositionResult[StateChapterSnapshot](status: reason(
          decoded.error)) # Child failure publishes no data.
    consumed = decoded.value.consumed # Each ordered roster uses its existing bounded population rules.
  of StateChapterId.Availability:
    let decoded = decodeAvailabilityState(input, AvailabilityConfig(guarantee: GuaranteeConfig(
        cores: profile.cores, validators: profile.current, maxBytes: policy.maxBytes),
        maxPresent: policy.items,
        maxBytes: policy.maxBytes))
    if decoded.error != AvailabilityError.None:
      return StateCompositionResult[StateChapterSnapshot](status: reason(
          decoded.error)) # Child failure publishes no data.
    consumed = decoded.value.consumed # Full optional guarantees use the shared core/current-validator profile.
  of StateChapterId.Time:
    let decoded = decodeStateTime(input)
    if decoded.error != StateComponentError.None:
      return StateCompositionResult[StateChapterSnapshot](status: reason(
          decoded.error)) # Child failure publishes no data.
    consumed = decoded.value.consumed # Timeslots remain exact E4 values.
  of StateChapterId.Privileges:
    let decoded = decodePrivilegeState(input, PrivilegeConfig(cores: profile.cores,
        maxAlways: policy.items, maxBytes: policy.maxBytes))
    if decoded.error != PrivilegeError.None:
      return StateCompositionResult[StateChapterSnapshot](status: reason(
          decoded.error)) # Child failure publishes no data.
    consumed = decoded.value.consumed # Privilege pairs use the migrated E4-service/E8-gas schema.
  of StateChapterId.Statistics:
    let decoded = decodeActivityState(input, ActivityConfig(cores: profile.cores,
        current: profile.current, previous: profile.previous, maxServices: policy.items,
        maxBytes: policy.maxBytes))
    if decoded.error != ActivityError.None:
      return StateCompositionResult[StateChapterSnapshot](status: reason(
          decoded.error)) # Child failure publishes no data.
    consumed = decoded.value.consumed # Statistics use E4 keys and vector-compatible compact gas, without a format fallback.
  of StateChapterId.Ready:
    let decoded = decodeReadyState(input, queues)
    if decoded.error != WorkQueueError.None:
      return StateCompositionResult[StateChapterSnapshot](status: reason(
          decoded.error)) # Child failure publishes no data.
    consumed = decoded.value.consumed # Ready rows retain full report/dependency validation.
  of StateChapterId.Accumulated:
    let decoded = decodeAccumulatedState(input, queues)
    if decoded.error != WorkQueueError.None:
      return StateCompositionResult[StateChapterSnapshot](status: reason(
          decoded.error)) # Child failure publishes no data.
    consumed = decoded.value.consumed # Accumulated rows retain canonical hash-set validation.
  of StateChapterId.Outputs:
    let decoded = decodeOutputLog(input, OutputLogConfig(items: policy.items,
        maxBytes: policy.maxBytes))
    if decoded.error != OutputLogError.None:
      return StateCompositionResult[StateChapterSnapshot](status: reason(
          decoded.error)) # Child failure publishes no data.
    consumed = decoded.value.consumed # The last-output sequence retains E4 service identities and ordered commitments.
  if consumed != input.len:
    return StateCompositionResult[StateChapterSnapshot](
        status: StateCompositionError.TrailingBytes) # Prefix success is not a complete state entry.
  let data = StateChapterData(chapter: chapter, profile: profile, bytes: @input)
  StateCompositionResult[StateChapterSnapshot](status: StateCompositionError.None,
    completed: StateChapterSnapshot(data: data))

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
proc composeState*(chapters: StateChapters,
    services: openArray[StateService], limits: StateTrieLimits,
    maxStorageKeyBytes: ByteLimit): StateCompositionResult[StateSnapshot] =
  var count = 0'u64
  var total = 0'u64
  ## Apply the same complete parent budget to chapters and every nested service entry.
  template account(size: untyped) =
    block:
      let error = charge(uint64(size), limits, count, total)
      if error != StateCompositionError.None:
        return StateCompositionResult[StateSnapshot](status: error) # No partial owner is published.
  let first = chapters[StateChapterId.Pools].data
  if first == nil:
    return StateCompositionResult[StateSnapshot](status: StateCompositionError.InvalidOwner) # Pools is inspected first in the same chapter order.
  # Inspect private captures before copying any payload or allocating the final mapping.
  for chapterNumber in ord(StateChapterId.Pools)..ord(StateChapterId.Outputs):
    let chapter = StateChapterId(chapterNumber)
    let part = chapters[chapter].data
    if part == nil:
      return StateCompositionResult[StateSnapshot](
          status: StateCompositionError.InvalidOwner) # Missing chapters cannot imply zero/default values.
    if part.chapter != chapter:
      return StateCompositionResult[StateSnapshot](
          status: StateCompositionError.WrongChapter) # A valid component cannot be relabeled.
    if not same(part.profile, first.profile):
      return StateCompositionResult[StateSnapshot](
          status: StateCompositionError.ProfileMismatch) # No mixing cardinality domains.
    account(part.bytes.len)
  # Traverse every nested descriptor before any service-key hashing or output-value copying.
  for service in services:
    account(ServiceMetadataBytes)
    for item in service.storage:
      if uint64(item.key.len) > uint64(maxStorageKeyBytes):
        return StateCompositionResult[StateSnapshot](
            status: StateCompositionError.LimitExceeded) # Raw key work has independent policy.
      account(item.value.len)
    for item in service.preimages:
      account(item.value.len) # Raw values have no count/length framing.
    for item in service.requests:
      account(historySize(item.history)) # Every tagged history has an exact fixed encoded extent.
    for item in service.captured:
      let info = serviceValueInfo(item)
      if info.error != ServiceValueError.None:
        return StateCompositionResult[StateSnapshot](
            status: StateCompositionError.InvalidOwner) # Default opaque handles cannot supply entries.
      if uint32(info.value.service) != uint32(service.service):
        return StateCompositionResult[StateSnapshot](
            status: StateCompositionError.InvalidComponent) # An opaque entry stays bound to its original service.
      account(info.value.length)
  var entries = newSeqOfCap[StateEntry](int(count))
  # Immutable chapter bytes can be retained safely; public extraction always returns independent copies.
  for chapterNumber in ord(StateChapterId.Pools)..ord(StateChapterId.Outputs):
    let chapter = StateChapterId(chapterNumber)
    let part = chapters[chapter].data
    assert part != nil # Complete immutable chapter preflight proved this retained source exists.
    entries.add(StateEntry(key: chapterKey(StateChapter(ord(chapter))), value: part.bytes))
  ## Existing entry encoders construct independent values and preserve nominal key/hash/history contracts.
  template append(expression, success: untyped) =
    block:
      let encoded = expression
      if encoded.error != success:
        return StateCompositionResult[StateSnapshot](status: reason(
            encoded.error)) # A failed key/child contributes no entry.
      entries.add(encoded.value)
  # Preserve source traversal order; the trie sorts private key indices and rejects all duplicates.
  for service in services:
    append(serviceMetadataEntry(service.service, service.metadata, limits.perValue),
        ServiceMetadataError.None)
    for item in service.storage:
      append(serviceStorageEntry(service.service, item.key, item.value,
        ServiceEntryLimits(keyBytes: maxStorageKeyBytes, valueBytes: limits.perValue)),
            ServiceValueError.None)
    for item in service.preimages:
      append(servicePreimageEntry(service.service, item.hash, item.value,
        ServiceEntryLimits(keyBytes: ByteLimit(32), valueBytes: limits.perValue)),
            ServiceValueError.None)
    for item in service.requests:
      append(serviceRequestEntry(service.service, item.hash, item.length, item.history,
        RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(
            items: ElementLimit(3), maxBytes: limits.perValue))), RequestError.None)
    for item in service.captured:
      append(serviceValueEntry(item, limits.perValue),
          ServiceValueError.None) # Previously captured raw values retain their exact existing key.
  let committed = stateTrieRoot(entries, limits)
  if committed.error != StateTrieError.None:
    return StateCompositionResult[StateSnapshot](status: reason(
        committed.error)) # Duplicates/topology/backend failures expose no root.
  StateCompositionResult[StateSnapshot](status: StateCompositionError.None,
    completed: StateSnapshot(data: StateCompositionData(entries: entries,
        commitment: committed.value)))

## Return a copied fixed commitment only from a complete immutable owner.
proc stateCommitment*(owner: StateSnapshot): StateCompositionResult[StateTrieCommitment] =
  let data = owner.data
  if data == nil:
    return StateCompositionResult[StateTrieCommitment](
        status: StateCompositionError.InvalidOwner) # No default state root.
  StateCompositionResult[StateTrieCommitment](status: StateCompositionError.None,
      completed: data.commitment)

## Copy one complete entry into independent caller-owned storage after nominal index validation.
proc stateEntryAt*(owner: StateSnapshot, index: StateEntryIndex): StateCompositionResult[StateEntry] =
  let data = owner.data
  if data == nil:
    return StateCompositionResult[StateEntry](status: StateCompositionError.InvalidOwner) # Missing owner cannot authorize extraction.
  if uint64(index) >= uint64(data.entries.len):
    return StateCompositionResult[StateEntry](status: StateCompositionError.InvalidIndex) # Validate before narrowing.
  let entry = data.entries[int(uint64(index))]
  var copy = StateEntry(key: entry.key, value: newSeq[byte](entry.value.len))
  # No exported mutable sequence aliases private chapter or composed-state storage.
  for i in 0..<copy.value.len: copy.value[i] = entry.value[i]
  StateCompositionResult[StateEntry](status: StateCompositionError.None, completed: copy)
