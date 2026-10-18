# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted native fixture constructors; expected transition rows are authored separately or
## pinned upstream.
##
## Exposes deterministic authorization hashes, profiles and source constructors, and re-exports
## their codec domains.

import std/assertions
import ../../src/codec/[state_authorization, assurances, bounded]
export state_authorization, assurances, bounded

## Simple distinct hashes keep oldest-occurrence and ordering expectations readable.
proc authHash*(number: byte): AuthorizerHash =
  var raw = default(array[32, byte])
  raw[0] = number
  AuthorizerHash(bytes: raw)

## Small explicit test profiles cover both components without guessing population from wire bytes.
proc authConfig*(cores = 2): AuthorizationConfig =
  assert cores >= 2 and cores <= 341
  AuthorizationConfig(cores: CoreCount(uint64(cores)), maxHashes: ElementLimit(uint64(cores)*80),
    maxBytes: ByteLimit(uint64(cores)*2561))

## Each queue position and core have distinct copied bytes, including positions 0 and 79.
proc authQueues*(cores = 2): seq[AuthorizerRow] =
  result = newSeq[AuthorizerRow](cores)
  for core in 0..<cores:
    result[core] = newSeq[AuthorizerHash](80)
    for index in 0..<80:
      var hash = authHash(byte(index))
      hash.bytes[1] = byte(core mod 256) # Position remains the first byte, core identity the second.
      result[core][index] = hash

## Build only valid immutable owners using already-tested component codecs, not a transition reference.
proc authOwner*(kind: AuthorizationKind, rows: seq[AuthorizerRow]): AuthorizationSnapshot =
  let config = authConfig(rows.len)
  let entry = authorizationEntry(kind, rows, config)
  assert entry.error == AuthorizationError.None
  let parsed = decodeAuthorization(kind, entry.value.value, config)
  assert parsed.error == AuthorizationError.None and parsed.value.consumed == entry.value.value.len
  parsed.value.snapshot
