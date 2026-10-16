## Supplementary ownership, copied-hash, index and guarded-result checks for authorization state.
import ../../src/[state_authorization, bounded, assurances]

## Retain Nim variant checks so failure/default results cannot masquerade as populated owners or hashes.
proc guarded[T](parsed: AuthorizationResult[T]) =
  var caught = false
  try:
    discard parsed.value # Inactive success fields must fail even in optimized builds.
  except FieldDefect:
    caught = true # Runtime field guards are required by the checked build contract.
  doAssert caught

## Validate retained data remains immutable under caller wire/source/copy/handle mutation.
proc main() =
  doAssert sizeof(int) == 8 and sizeof(AuthorizerRow) == 16
  let policy = AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(160),
      maxBytes: ByteLimit(5120))
  var hash: AuthorizerHash
  hash.bytes[0] = 17
  var source = @[@[hash, hash], newSeq[AuthorizerHash]()]
  let encoded = authorizationEntry(AuthorizationKind.Pools, source, policy)
  doAssert encoded.error == AuthorizationError.None
  source[0][0].bytes[0] = 99
  doAssert encoded.value.value[1] == 17
  var wire = encoded.value.value
  let decoded = decodeAuthorization(AuthorizationKind.Pools, wire, policy)
  doAssert decoded.error == AuthorizationError.None
  let retained = decoded.value.snapshot
  # Destroy the complete caller wire after private capture.
  for i in 0..<wire.len: wire[i] = 0
  doAssert authorizationKind(retained).value == AuthorizationKind.Pools
  doAssert authorizationCores(retained).value == 2
  doAssert authorizerCount(retained, AuthorizationCoreIndex(0)).value == 2
  doAssert authorizerCount(retained, AuthorizationCoreIndex(1)).value == 0
  let first = authorizerAt(retained, AuthorizationCoreIndex(0), AuthorizationIndex(0))
  doAssert first.error == AuthorizationError.None and first.value.bytes[0] == 17
  var copied = first.value
  copied.bytes[0] = 255
  doAssert authorizerAt(retained, AuthorizationCoreIndex(0), AuthorizationIndex(0)).value.bytes[0] == 17
  var replaced = retained
  replaced = default(AuthorizationSnapshot)
  doAssert authorizationCores(retained).value == 2
  doAssert authorizationKind(replaced).error == AuthorizationError.InvalidOwner
  guarded(authorizationCores(replaced))
  guarded(authorizerAt(replaced, AuthorizationCoreIndex(0), AuthorizationIndex(0)))
  let badCore = authorizerCount(retained, AuthorizationCoreIndex(high(uint64)))
  doAssert badCore.error == AuthorizationError.InvalidIndex
  guarded(badCore)
  let emptyRow = authorizerAt(retained, AuthorizationCoreIndex(1), AuthorizationIndex(0))
  doAssert emptyRow.error == AuthorizationError.InvalidIndex
  guarded(emptyRow)
  let badIndex = authorizerAt(retained, AuthorizationCoreIndex(0), AuthorizationIndex(high(uint64)))
  doAssert badIndex.error == AuthorizationError.InvalidIndex
  guarded(badIndex)
  guarded(default(AuthorizationResult[AuthorizationRead]))
  let truncated = decodeAuthorization(AuthorizationKind.Pools, @[0'u8], policy)
  doAssert truncated.error == AuthorizationError.Truncated
  guarded(truncated)
  let invalid = authorizationEntry(AuthorizationKind.Queues, source, policy)
  doAssert invalid.error == AuthorizationError.InvalidCount
  guarded(invalid)
  let empty = authorizationEntry(AuthorizationKind.Pools, [newSeq[AuthorizerHash](), newSeq[
      AuthorizerHash]()], policy)
  doAssert empty.error == AuthorizationError.None and empty.value.value == @[0'u8, 0]
  echo "PASS authorization state: immutable ownership, copied hashes, empty pools, indices and result guards"

main()
