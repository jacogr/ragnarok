## Isolated default/failed authorization result reads cover entries, owners, counts, hashes and private framing.
import std/[assertions, cmdline, syncio]
include ../../src/codec/state_authorization
let useDefault = paramStr(2) == "default"
let policy = AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(160),
    maxBytes: ByteLimit(5120))
let strict = AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(0),
    maxBytes: ByteLimit(5120))
let invalidConfig = AuthorizationConfig(cores: CoreCount(1), maxHashes: ElementLimit(160),
    maxBytes: ByteLimit(5120))
let huge = AuthorizationConfig(cores: CoreCount(high(uint64)), maxHashes: ElementLimit(high(
    uint64)), maxBytes: ByteLimit(high(uint64)))
let rows = @[newSeq[AuthorizerHash](1), newSeq[AuthorizerHash](0)]
let encoded = authorizationEntry(AuthorizationKind.Pools, rows, policy)
assert encoded.error == AuthorizationError.None
let decoded = decodeAuthorization(AuthorizationKind.Pools, encoded.value.value, policy)
assert decoded.error == AuthorizationError.None
let owner = decoded.value.snapshot
case paramStr(1)
of "entry-shape":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[StateEntry]) else: authorizationEntry(
      AuthorizationKind.Pools, [], policy)
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidCount)
  echo parsed.value.value.len
of "entry-kind":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[StateEntry]) else: authorizationEntry(
      AuthorizationKind(2), rows, policy)
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidTag)
  echo parsed.value.value.len
of "entry-config":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[StateEntry]) else: authorizationEntry(
      AuthorizationKind.Pools, rows, invalidConfig)
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidConfig)
  echo parsed.value.value.len
of "entry-policy":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[StateEntry]) else: authorizationEntry(
      AuthorizationKind.Pools, rows, strict)
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.LimitExceeded)
  echo parsed.value.value.len
of "snapshot":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[
      AuthorizationRead]) else: decodeAuthorization(AuthorizationKind.Pools, [], policy)
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.Truncated)
  echo authorizationCores(parsed.value.snapshot).value
of "consumed":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[
      AuthorizationRead]) else: decodeAuthorization(AuthorizationKind.Pools, [], policy)
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.Truncated)
  echo parsed.value.consumed
of "decode-kind":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[
      AuthorizationRead]) else: decodeAuthorization(AuthorizationKind(2), [], policy)
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidTag)
  echo parsed.value.consumed
of "decode-config":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[
      AuthorizationRead]) else: decodeAuthorization(AuthorizationKind.Pools, [], invalidConfig)
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidConfig)
  echo parsed.value.consumed
of "decode-count":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[
      AuthorizationRead]) else: decodeAuthorization(AuthorizationKind.Pools, [0'u8, 9], policy)
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidCount)
  echo parsed.value.consumed
of "decode-noncanonical":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[
      AuthorizationRead]) else: decodeAuthorization(AuthorizationKind.Pools, [0'u8, 128, 0], policy)
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.NonCanonical)
  echo parsed.value.consumed
of "decode-policy":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[
      AuthorizationRead]) else: decodeAuthorization(AuthorizationKind.Pools, [1'u8], strict)
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.LimitExceeded)
  echo parsed.value.consumed
of "decode-overflow":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[
      AuthorizationRead]) else: decodeAuthorization(AuthorizationKind.Pools, [], huge)
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.LengthOverflow)
  echo parsed.value.consumed
of "kind":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[
      AuthorizationKind]) else: authorizationKind(default(AuthorizationSnapshot))
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidOwner)
  echo ord(parsed.value)
of "cores":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[int]) else: authorizationCores(default(AuthorizationSnapshot))
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidOwner)
  echo parsed.value
of "count-owner":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[int]) else: authorizerCount(default(
      AuthorizationSnapshot), AuthorizationCoreIndex(0))
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidOwner)
  echo parsed.value
of "count-index":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[int]) else: authorizerCount(owner,
      AuthorizationCoreIndex(high(uint64)))
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidIndex)
  echo parsed.value
of "hash-owner":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[AuthorizerHash]) else: authorizerAt(
      default(AuthorizationSnapshot), AuthorizationCoreIndex(0), AuthorizationIndex(0))
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidOwner)
  echo parsed.value.bytes[0]
of "hash-core":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[AuthorizerHash]) else: authorizerAt(owner,
      AuthorizationCoreIndex(high(uint64)), AuthorizationIndex(0))
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidIndex)
  echo parsed.value.bytes[0]
of "hash-index":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[AuthorizerHash]) else: authorizerAt(owner,
      AuthorizationCoreIndex(0), AuthorizationIndex(high(uint64)))
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidIndex)
  echo parsed.value.bytes[0]
of "hash-empty":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[AuthorizerHash]) else: authorizerAt(owner,
      AuthorizationCoreIndex(1), AuthorizationIndex(0))
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.InvalidIndex)
  echo parsed.value.bytes[0]
of "tuple-count":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[tuple[count: uint64,
      prefix: int]]) else: poolCount([])
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.Truncated)
  echo parsed.value.count
of "tuple-prefix":
  # A failed/default operation cannot authorize this entry, owner, field or progress observation.
  let parsed = if useDefault: default(AuthorizationResult[tuple[count: uint64,
      prefix: int]]) else: poolCount([128'u8, 0])
  assert parsed.error == (if useDefault: AuthorizationError.Uninitialized else: AuthorizationError.NonCanonical)
  echo parsed.value.prefix
else:
  # Unknown selectors are harness errors, never successful guard evidence.
  quit(2)
