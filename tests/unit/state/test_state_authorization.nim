# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Supplementary ownership, copied-hash, index and guarded-result checks for authorization
## state.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio]
import ../../../src/codec/state/authorization as state_authorization
import ../../../src/codec/[bounded, assurances]

## Validate retained data remains immutable under caller wire/source/copy/handle mutation.
proc main() =
  assert sizeof(int) == 8 and sizeof(AuthorizerRow) == 16
  let policy = AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(160),
      maxBytes: ByteLimit(5120))
  var hash = default(AuthorizerHash)
  hash.bytes[0] = 17
  var source = @[@[hash, hash], newSeq[AuthorizerHash]()]
  let encoded = authorizationEntry(AuthorizationKind.Pools, source, policy)
  assert encoded.error == AuthorizationError.None
  source[0][0].bytes[0] = 99
  assert encoded.value.value[1] == 17
  var wire = encoded.value.value
  let decoded = decodeAuthorization(AuthorizationKind.Pools, wire, policy)
  assert decoded.error == AuthorizationError.None
  let retained = decoded.value.snapshot
  # Destroy the complete caller wire after private capture.
  for i in 0..<wire.len: wire[i] = 0
  assert authorizationKind(retained).value == AuthorizationKind.Pools
  assert authorizationCores(retained).value == 2
  assert authorizerCount(retained, AuthorizationCoreIndex(0)).value == 2
  assert authorizerCount(retained, AuthorizationCoreIndex(1)).value == 0
  let first = authorizerAt(retained, AuthorizationCoreIndex(0), AuthorizationIndex(0))
  assert first.error == AuthorizationError.None and first.value.bytes[0] == 17
  var copied = first.value
  copied.bytes[0] = 255
  assert authorizerAt(retained, AuthorizationCoreIndex(0), AuthorizationIndex(0)).value.bytes[0] == 17
  var replaced = retained
  replaced = default(AuthorizationSnapshot)
  assert authorizationCores(retained).value == 2
  assert authorizationKind(replaced).error == AuthorizationError.InvalidOwner
  let badCore = authorizerCount(retained, AuthorizationCoreIndex(high(uint64)))
  assert badCore.error == AuthorizationError.InvalidIndex
  let emptyRow = authorizerAt(retained, AuthorizationCoreIndex(1), AuthorizationIndex(0))
  assert emptyRow.error == AuthorizationError.InvalidIndex
  let badIndex = authorizerAt(retained, AuthorizationCoreIndex(0), AuthorizationIndex(high(uint64)))
  assert badIndex.error == AuthorizationError.InvalidIndex
  # Failed/default payload reads run in isolated processes in the trial runner.
  assert authorizationCores(replaced).error == AuthorizationError.InvalidOwner
  assert authorizerAt(replaced, AuthorizationCoreIndex(0), AuthorizationIndex(0)).error ==
      AuthorizationError.InvalidOwner
  let truncated = decodeAuthorization(AuthorizationKind.Pools, @[0'u8], policy)
  assert truncated.error == AuthorizationError.Truncated
  let invalid = authorizationEntry(AuthorizationKind.Queues, source, policy)
  assert invalid.error == AuthorizationError.InvalidCount
  let empty = authorizationEntry(AuthorizationKind.Pools, [newSeq[AuthorizerHash](), newSeq[
      AuthorizerHash]()], policy)
  assert empty.error == AuthorizationError.None and empty.value.value == @[0'u8, 0]
  # Exhaust every underlying kind octet because integer-to-enum conversion is unchecked in this nightly.
  for ordinal in 0..255:
    let kind = AuthorizationKind(ordinal)
    let candidate = authorizationEntry(kind, source, policy)
    let parsed = decodeAuthorization(kind, [0'u8, 0], policy)
    if ordinal == 0:
      # Pools retain their exact namespace and implicit two-core framing.
      assert candidate.error == AuthorizationError.None
      assert array[31, byte](candidate.value.key)[0] == 1
      assert parsed.error == AuthorizationError.None
    elif ordinal == 1:
      # A valid queue kind still enforces its own shape and complete fixed payload.
      assert candidate.error == AuthorizationError.InvalidCount
      assert parsed.error == AuthorizationError.Truncated
    else:
      # No invalid kind may select the queue fallback or bypass cardinality checks.
      assert candidate.error == AuthorizationError.InvalidTag
      assert parsed.error == AuthorizationError.InvalidTag
  echo "PASS authorization state: immutable ownership, copied hashes, empty pools, indices and result guards"

main()
