# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Structural ancestry witnesses use explicitly authored sealed-header bytes without claiming signature or execution validity.
import std/assertions
import ./fuzz_protocol_context
import ../../src/state/fuzz/[protocol as fuzz_protocol, ancestry as fuzz_ancestry]
import ../../src/codec/[bounded, header]
import ../../src/crypto/primitives
proc fuzzAncestryTestLimits*(): FuzzAncestryLimits =
  ## Keep exact Tiny header domains and independent finite context retention quotas.
  let wire = fuzzProtocolTestLimits().frame
  FuzzAncestryLimits(header: HeaderConfig(cores: wire.cores, authorValidators: wire.validators,
    epochSlots: wire.epochSlots, maxBytes: ByteLimit(4096)), records: ElementLimit(24),
        bytes: ByteLimit(16384))
proc ancestryWord*(value: byte): array[32, byte] =
  ## Fixed words make independent parent/root mismatches visible without ambiguous zero sentinels.
  result = default(array[32, byte])
  for index in 0..<result.len: result[index] = value # Each word is copied by value into its nominal domain.
proc ancestryHeader*(slot: HeaderSlot, parent: FuzzHeaderHash, root: PriorStateRoot): OwnedHeader =
  ## Encode one canonical absent-marker/empty-offender header with an opaque zero seal for structural evidence tests.
  let limits = fuzzAncestryTestLimits()
  var value = default(Header)
  value.unsigned.epoch = absentEpoch()
  value.unsigned.winners = absentWinners()
  value.unsigned.slot = slot
  value.unsigned.parent = HeaderParent(array[32, byte](parent))
  value.unsigned.priorState = root
  var bytes = newSeq[byte](4096)
  let encoded = encodeHeader(value, limits.header, bytes)
  assert encoded.error == HeaderError.None
  bytes.setLen(encoded.value)
  let decoded = decodeHeader(bytes, limits.header)
  assert decoded.error == HeaderError.None
  decoded.value.owner
proc ancestryHash*(header: OwnedHeader): FuzzHeaderHash =
  ## The exact complete seal participates in the identity, independently of all state roots.
  var bytes = newSeq[byte](header.headerInfo.value.consumed)
  assert header.encodeOwnedHeader(bytes).error == HeaderError.None
  let hashed = blake2b256(bytes)
  assert hashed.error == CryptoError.None
  FuzzHeaderHash(array[32, byte](hashed.value))
