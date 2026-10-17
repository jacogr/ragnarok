## GP 0.8.0 authorization pool transition, authorization.tex and notation.tex sequence operators.
## Queue inputs must already reflect accumulation; guarantee core/hash projections are caller-validated.
import ../codec/[state_authorization, state_layout, state_trie, bounded]
import ./store

type
  ## Header timeslot domain, distinct from core/row positions and other arbitrary integers.
  AuthorizationSlot* = distinct uint32
  ## Exactly the guarantee fields used by this subsystem, not a signature or membership validation result.
  CoreAuthorizer* = object
    core*: AuthorizationCoreIndex
    authorizer*: AuthorizerHash
  ## Transition failures expose no proposed entry, root or progress.
  AuthorizationTransitionError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidState, InvalidCore, DuplicateCore,
    LimitExceeded, LengthOverflow, MissingState, BackendFailure
  ## Success alone exposes a complete serialized entry or committed store snapshot.
  AuthorizationTransitionResult*[T] = object
    case status: AuthorizationTransitionError
    of None:
      completed: T # Result access remains guarded in optimized builds.
    else:
      discard      # Defaults and failures carry their reason only.
  ## A bounded per-core plan preserves the removal position and source/output lengths until allocation.
  PoolPlan = object
    sourceCount: int
    removed: int
    count: int

## Inspect a failure without granting payload or discriminator mutation access.
func error*[T](outcome: AuthorizationTransitionResult[
    T]): AuthorizationTransitionError = outcome.status

## Extract only complete success; failure/default payloads do not exist.
func value*[T](outcome: AuthorizationTransitionResult[T]): T {.inline,
    requires: outcome.status == AuthorizationTransitionError.None.} = outcome.completed

## Preserve policy and native-extent failures; other codec failures identify invalid supplied state.
func codecError(reason: AuthorizationError): AuthorizationTransitionError =
  case reason
  of AuthorizationError.None: AuthorizationTransitionError.None # Complete codec success only.
  of AuthorizationError.InvalidConfig: AuthorizationTransitionError.InvalidConfig # Do not infer profiles.
  of AuthorizationError.LimitExceeded: AuthorizationTransitionError.LimitExceeded # Keep caller limits explicit.
  of AuthorizationError.LengthOverflow: AuthorizationTransitionError.LengthOverflow # Never narrow unsafe extents.
  else: AuthorizationTransitionError.InvalidState # Invalid owners, kinds, shapes and framing are not state.

## Preserve store initialization, absence, policy and primitive refusal without manufacturing a commitment.
func storeError(reason: StateStoreError): AuthorizationTransitionError =
  case reason
  of StateStoreError.None: AuthorizationTransitionError.None # Only a complete atomic commit succeeds.
  of StateStoreError.Uninitialized: AuthorizationTransitionError.Uninitialized # Default handles are not empty states.
  of StateStoreError.MissingKey: AuthorizationTransitionError.MissingState # Both chapter entries are required.
  of StateStoreError.LimitExceeded: AuthorizationTransitionError.LimitExceeded # A refused write leaves the old head.
  of StateStoreError.LengthOverflow: AuthorizationTransitionError.LengthOverflow # Preserve native addressing failures.
  of StateStoreError.BackendFailure: AuthorizationTransitionError.BackendFailure # Hash failure cannot become a root.
  else: AuthorizationTransitionError.InvalidState # No other store failure is valid transition input/output.

## Compute C(1) after removing one oldest used hash, appending the post-accumulation queue item,
## and retaining the newest eight entries. Inputs are immutable retained snapshots, never borrowed rows.
## Guarantees are already validated by the caller; duplicate core projections reject instead of choosing one.
proc advanceAuthorization*(pools, postQueues: AuthorizationSnapshot,
    uses: openArray[CoreAuthorizer], slot: AuthorizationSlot,
    config: AuthorizationConfig): AuthorizationTransitionResult[StateEntry] =
  if uint64(config.cores) < 2:
    # Match the codec's explicit configured population instead of guessing tiny/full from inputs.
    return AuthorizationTransitionResult[StateEntry](
        status: AuthorizationTransitionError.InvalidConfig)
  let poolKind = authorizationKind(pools)
  let queueKind = authorizationKind(postQueues)
  if poolKind.error != AuthorizationError.None or queueKind.error != AuthorizationError.None:
    # A default retained owner cannot authorize row access or imply an empty component.
    return AuthorizationTransitionResult[StateEntry](
        status: AuthorizationTransitionError.InvalidState)
  if poolKind.value != AuthorizationKind.Pools or queueKind.value != AuthorizationKind.Queues:
    # The same hash bytes do not make the two component roles interchangeable.
    return AuthorizationTransitionResult[StateEntry](
        status: AuthorizationTransitionError.InvalidState)
  let poolCores = authorizationCores(pools)
  let queueCores = authorizationCores(postQueues)
  if poolCores.error != AuthorizationError.None or queueCores.error != AuthorizationError.None:
    return AuthorizationTransitionResult[StateEntry](
        status: AuthorizationTransitionError.InvalidState) # No safe extent.
  if uint64(poolCores.value) != uint64(config.cores) or poolCores.value != queueCores.value:
    # All core rows and the explicit caller profile must describe the same population.
    return AuthorizationTransitionResult[StateEntry](
        status: AuthorizationTransitionError.InvalidConfig)
  let cores = poolCores.value
  if cores > high(int) div sizeof(PoolPlan) or cores > high(int) div sizeof(AuthorizerRow) or
      cores > high(int) div sizeof(int):
    # Every input-derived scratch/row descriptor extent must fit before allocation.
    return AuthorizationTransitionResult[StateEntry](
        status: AuthorizationTransitionError.LengthOverflow)
  if uint64(cores) > uint64(config.maxHashes) or uint64(cores) > uint64(config.maxBytes) div 33:
    # Appending the queue item gives every output pool at least one hash plus its count byte.
    return AuthorizationTransitionResult[StateEntry](
        status: AuthorizationTransitionError.LimitExceeded)
  if uses.len > cores:
    # A valid guarantees projection has at most one entry per configured core.
    return AuthorizationTransitionResult[StateEntry](
        status: AuthorizationTransitionError.DuplicateCore)
  # Validate nominal core ordinals before native conversion or scratch indexing.
  for use in uses:
    if uint64(use.core) >= uint64(cores):
      return AuthorizationTransitionResult[StateEntry](
          status: AuthorizationTransitionError.InvalidCore)
  var used = newSeq[int](cores)
  for i in 0..<cores: used[i] = -1 # No projection is assigned until its core passes duplicate checking.
  for i, use in uses:
    let core = int(uint64(use.core))
    if used[core] >= 0:
      # Do not invent which authorizer the existential equation means for a malformed duplicate core.
      return AuthorizationTransitionResult[StateEntry](
          status: AuthorizationTransitionError.DuplicateCore)
    used[core] = i
  var plans = newSeq[PoolPlan](cores)
  var hashes = 0'u64
  var bytes = cores # Counts 0..8 all have one canonical natural byte.
                    # Preflight the complete output before allocating any pool payload rows.
  for core in 0..<cores:
    let ordinal = AuthorizationCoreIndex(uint64(core))
    let count = authorizerCount(pools, ordinal)
    let queueCount = authorizerCount(postQueues, ordinal)
    if count.error != AuthorizationError.None or queueCount.error != AuthorizationError.None:
      return AuthorizationTransitionResult[StateEntry](
          status: AuthorizationTransitionError.InvalidState) # No complete row.
    if count.value > 8 or queueCount.value != 80:
      return AuthorizationTransitionResult[StateEntry](
          status: AuthorizationTransitionError.InvalidState) # Pinned cardinalities.
    var removed = -1
    if used[core] >= 0:
      # Sequence subtraction removes the first match only, preserving later equal authorizers.
      for position in 0..<count.value:
        let hash = authorizerAt(pools, ordinal, AuthorizationIndex(uint64(position)))
        if hash.error != AuthorizationError.None:
          return AuthorizationTransitionResult[StateEntry](
              status: AuthorizationTransitionError.InvalidState)
        if hash.value.bytes == uses[used[core]].authorizer.bytes:
          removed = position
          break # The oldest matching occurrence is the only subtraction.
    let outCount = min(8, count.value+1-(if removed >= 0: 1 else: 0))
    if uint64(outCount) > uint64(config.maxHashes)-hashes:
      return AuthorizationTransitionResult[StateEntry](
          status: AuthorizationTransitionError.LimitExceeded) # Check before sum.
    if outCount > (high(int)-bytes) div 32:
      return AuthorizationTransitionResult[StateEntry](
          status: AuthorizationTransitionError.LengthOverflow) # Check before multiply.
    bytes += outCount*32
    hashes += uint64(outCount)
    if uint64(bytes) > uint64(config.maxBytes):
      return AuthorizationTransitionResult[StateEntry](
          status: AuthorizationTransitionError.LimitExceeded) # Include every count prefix.
    plans[core] = PoolPlan(sourceCount: count.value, removed: removed, count: outCount)
  var rows = newSeq[AuthorizerRow](cores)
  let queuePosition = AuthorizationIndex(uint64(uint32(slot) mod 80'u32))
  # A nine-element stack buffer bounds each row before newest-eight truncation and immutable serialization.
  for core in 0..<cores:
    let ordinal = AuthorizationCoreIndex(uint64(core))
    var selected = default(array[9, AuthorizerHash])
    var length = 0
    for position in 0..<plans[core].sourceCount:
      if position != plans[core].removed:
        # Preserve the original order of every non-removed occurrence.
        let hash = authorizerAt(pools, ordinal, AuthorizationIndex(uint64(position)))
        if hash.error != AuthorizationError.None:
          return AuthorizationTransitionResult[StateEntry](
              status: AuthorizationTransitionError.InvalidState)
        selected[length] = hash.value
        inc length
    let next = authorizerAt(postQueues, ordinal, queuePosition)
    if next.error != AuthorizationError.None:
      return AuthorizationTransitionResult[StateEntry](
          status: AuthorizationTransitionError.InvalidState) # No queue fallback.
    selected[length] = next.value
    inc length
    rows[core] = newSeq[AuthorizerHash](plans[core].count)
    let start = length-plans[core].count
    for i in 0..<rows[core].len: rows[core][i] = selected[start+i] # Keep the newest suffix without deduplication.
  let encoded = authorizationEntry(AuthorizationKind.Pools, rows, config)
  if encoded.error != AuthorizationError.None:
    return AuthorizationTransitionResult[StateEntry](status: codecError(
        encoded.error)) # Never expose partial bytes.
  AuthorizationTransitionResult[StateEntry](status: AuthorizationTransitionError.None,
      completed: encoded.value)

## Read complete C(1)/C(2) values from a full-state working store after accumulation and atomically
## publish C(1) only. C(2) is already posterior and is neither rotated nor rewritten by this subsystem.
proc advanceAuthorizationState*(state: var StateStore, uses: openArray[CoreAuthorizer],
    slot: AuthorizationSlot, config: AuthorizationConfig): AuthorizationTransitionResult[
        StateStoreSnapshot] =
  let before = state.snapshot
  if before.error != StateStoreError.None:
    return AuthorizationTransitionResult[StateStoreSnapshot](status: storeError(
        before.error)) # Default store is not state.
  let poolBytes = before.value.lookup(chapterKey(StateChapter(1)))
  if poolBytes.error != StateStoreError.None:
    return AuthorizationTransitionResult[StateStoreSnapshot](status: storeError(
        poolBytes.error)) # Missing pools cannot be inferred.
  let queueBytes = before.value.lookup(chapterKey(StateChapter(2)))
  if queueBytes.error != StateStoreError.None:
    return AuthorizationTransitionResult[StateStoreSnapshot](status: storeError(
        queueBytes.error)) # Missing queues cannot be inferred.
  if uint64(poolBytes.value.byteLength) > uint64(config.maxBytes) or uint64(
      queueBytes.value.byteLength) > uint64(config.maxBytes):
    # Check stored entry extents before copying potentially untrusted raw values into decoder inputs.
    return AuthorizationTransitionResult[StateStoreSnapshot](
        status: AuthorizationTransitionError.LimitExceeded)
  let rawPools = poolBytes.value.bytes
  let rawQueues = queueBytes.value.bytes
  let pools = decodeAuthorization(AuthorizationKind.Pools, rawPools, config)
  if pools.error != AuthorizationError.None:
    return AuthorizationTransitionResult[StateStoreSnapshot](status: codecError(
        pools.error)) # No malformed state repair.
  let queues = decodeAuthorization(AuthorizationKind.Queues, rawQueues, config)
  if queues.error != AuthorizationError.None:
    return AuthorizationTransitionResult[StateStoreSnapshot](status: codecError(
        queues.error)) # No alternate queue encoding.
  if pools.value.consumed != rawPools.len or queues.value.consumed != rawQueues.len:
    return AuthorizationTransitionResult[StateStoreSnapshot](
        status: AuthorizationTransitionError.InvalidState) # Exact chapter entries.
  let advanced = advanceAuthorization(pools.value.snapshot, queues.value.snapshot, uses, slot, config)
  if advanced.error != AuthorizationTransitionError.None:
    return AuthorizationTransitionResult[StateStoreSnapshot](
        status: advanced.error) # No write before whole transition success.
  let committed = state.apply(@[StateWrite(key: advanced.value.key, kind: StateWriteKind.Put,
      value: advanced.value.value)])
  if committed.error != StateStoreError.None:
    return AuthorizationTransitionResult[StateStoreSnapshot](status: storeError(
        committed.error)) # Atomic rollback belongs to the store.
  AuthorizationTransitionResult[StateStoreSnapshot](status: AuthorizationTransitionError.None,
      completed: committed.value)
