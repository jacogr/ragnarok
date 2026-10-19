# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Project-only white-box arithmetic and public ownership cycles; no private compiler/runtime
## API is used.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

## Verification: {"arc": "authorization_arc_release"}

import std/[assertions, syncio]
import ../../support/arc_evidence
include ../../../src/codec/state_authorization

# Return an immutable owner after all local source rows, entry bytes and wire aliases have retired.
proc escaped(kind: AuthorizationKind, marker: byte): AuthorizationSnapshot =
  let policy = AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(160),
      maxBytes: ByteLimit(5120))
  var source = newSeq[AuthorizerRow](2)
  # Pools include an empty core; queues retain every fixed position in both core rows.
  for core in 0..<2:
    let count = if kind == AuthorizationKind.Pools: (if core == 0: 2 else: 0) else: 80
    source[core] = newSeq[AuthorizerHash](count)
    # Patterned fixed hashes expose field order and independence after caller mutation.
    for i in 0..<count: source[core][i].bytes[0] = byte(int(marker)+core+i)
  let encoded = authorizationEntry(kind, source, policy)
  assert encoded.error == AuthorizationError.None
  var wire = encoded.value.value
  let decoded = decodeAuthorization(kind, wire, policy)
  assert decoded.error == AuthorizationError.None
  result = decoded.value.snapshot
  # Neither wire nor nested source rows may remain as backing storage for retained hashes.
  for i in 0..<wire.len: wire[i] = 0
  for core in 0..<source.len:
    for i in 0..<source[core].len: source[core][i] = default(AuthorizerHash)

# Every scope drops replaced/retained pool and queue owners and all copied/error temporaries.
proc cycle() =
  let policy = AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(160),
      maxBytes: ByteLimit(5120))
  var owner = escaped(AuthorizationKind.Pools, 17)
  let alias = owner
  owner = escaped(AuthorizationKind.Pools, 29)
  let queue = escaped(AuthorizationKind.Queues, 43)
  assert authorizerAt(alias, AuthorizationCoreIndex(0), AuthorizationIndex(0)).value.bytes[0] == 17
  assert authorizerAt(owner, AuthorizationCoreIndex(0), AuthorizationIndex(0)).value.bytes[0] == 29
  assert authorizationKind(queue).value == AuthorizationKind.Queues
  assert authorizerCount(queue, AuthorizationCoreIndex(1)).value == 80
  assert authorizerAt(queue, AuthorizationCoreIndex(1), AuthorizationIndex(79)).value.bytes[0] == 123
  var copy = authorizerAt(alias, AuthorizationCoreIndex(0), AuthorizationIndex(0)).value
  copy.bytes[0] = 255
  assert authorizerAt(alias, AuthorizationCoreIndex(0), AuthorizationIndex(0)).value.bytes[0] == 17
  owner = default(AuthorizationSnapshot)
  assert authorizationKind(owner).error == AuthorizationError.InvalidOwner
  assert authorizationCores(alias).value == 2
  assert authorizerCount(alias, AuthorizationCoreIndex(high(uint64))).error ==
      AuthorizationError.InvalidIndex
  assert authorizerAt(alias, AuthorizationCoreIndex(0), AuthorizationIndex(high(uint64))).error ==
      AuthorizationError.InvalidIndex
  assert authorizerAt(alias, AuthorizationCoreIndex(1), AuthorizationIndex(0)).error ==
      AuthorizationError.InvalidIndex
  assert decodeAuthorization(AuthorizationKind.Pools, [0'u8], policy).error ==
      AuthorizationError.Truncated
  assert decodeAuthorization(AuthorizationKind.Pools, [0'u8, 128, 0], policy).error ==
      AuthorizationError.NonCanonical
  assert decodeAuthorization(AuthorizationKind.Pools, [0'u8, 9], policy).error ==
      AuthorizationError.InvalidCount
  let invalid = @[newSeq[AuthorizerHash](2), newSeq[AuthorizerHash](9)]
  assert authorizationEntry(AuthorizationKind.Pools, invalid, policy).error ==
      AuthorizationError.InvalidCount

let broad = AuthorizationConfig(cores: CoreCount(2), maxHashes: ElementLimit(high(uint64)),
    maxBytes: ByteLimit(high(uint64)))
# Exhaust the aggregate hash budget without allowing wrapping into a small successful count.
var layout = Layout(bytes: 0, hashes: high(uint64)-1)
assert charge(AuthorizationKind.Pools, 1, 1, broad, layout) == AuthorizationError.None
assert layout.hashes == high(uint64) and layout.bytes == 33
assert charge(AuthorizationKind.Pools, 1, 1, broad, layout) == AuthorizationError.LimitExceeded
assert layout.hashes == high(uint64) and layout.bytes == 33
# Prefix and stride arithmetic reject before addition/multiplication at the signed native extent ceiling.
layout = Layout(bytes: high(int)-1, hashes: 0)
assert charge(AuthorizationKind.Pools, 0, 1, broad, layout) == AuthorizationError.None
assert layout.bytes == high(int)
assert charge(AuthorizationKind.Pools, 0, 1, broad, layout) == AuthorizationError.LengthOverflow
assert layout.bytes == high(int)
layout = Layout(bytes: high(int)-32, hashes: 0)
assert charge(AuthorizationKind.Pools, 1, 1, broad, layout) == AuthorizationError.LengthOverflow
assert layout.bytes == high(int)-32
let huge = AuthorizationConfig(cores: CoreCount(high(uint64)), maxHashes: broad.maxHashes,
    maxBytes: broad.maxBytes)
assert validate(AuthorizationKind.Pools, huge) == AuthorizationError.LengthOverflow
assert validate(AuthorizationKind.Queues, huge) == AuthorizationError.LengthOverflow
# Warmup excludes allocator initialization from the isolated retained-owner release comparison.
for i in 0..<100: cycle()
let beforeRelease = getOccupiedMem()
# Each iteration releases every callee-local entry, nested source, snapshot and replaced/retained handle.
for i in 0..<1000: cycle()
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("state_authorization_private", 1000, beforeRelease, afterRelease)
echo "AUTHORIZATION_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony authorization: escaped/replaced pool/queue owners, copied hashes, arithmetic and scoped ARC release passed"
