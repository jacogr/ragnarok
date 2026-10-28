# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-only fuzzer request construction composes exact existing immutable child encodings.
import std/assertions
import ./app_fuzz_protocol_context
import ./state_current_consecutive_context
import ./state_accumulation_current_chain_context
import ../../src/app/fuzz_backend as app_fuzz_backend
import ../../src/state/fuzz_protocol as state_fuzz_protocol
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/header as codec_header
import ../../src/codec/block_codec as codec_block_codec
import ../../src/crypto/primitives as crypto_primitives
proc fuzzBackendTestConfig*(): FuzzBackendConfig =
  ## Keep the independently frozen current STF profile and explicit resource policies.
  FuzzBackendConfig(parameters: currentChainSettings(), candidate: currentConsecutiveLimits(),
      wire: fuzzProtocolTestLimits())
proc fuzzInitialize*(header: OwnedHeader, state: StateStoreSnapshot, ancestry: openArray[
    FuzzAncestor] = [], limits: FuzzLimits = fuzzProtocolTestLimits()): FuzzMessage =
  ## An Initialize contains exact header bytes, a rootless complete map and explicit test membership.
  var wire = @[1'u8]
  var head = newSeq[byte](header.headerInfo.value.consumed)
  assert header.encodeOwnedHeader(head).error == HeaderError.None
  for octet in head: wire.add(octet) # Child serialization is unchanged before enclosing composition.
  let serialized = newFuzzState(state, limits).value.copyFuzzMessage(limits.bytes).value
  for index in 1..<serialized.len: wire.add(serialized[
      index]) # Replace only State's discriminant, retaining the rootless map.
  assert ancestry.len <= 24
  wire.add(byte(ancestry.len))
  for member in ancestry:
    for shift in 0..<4: wire.add(byte((uint32(member.slot) shr (shift*8)) and 255))
    for octet in array[32, byte](member.hash): wire.add(octet) # Only hash/slot facts are supplied on the wire.
  let decoded = decodeFuzzMessage(wire, limits)
  assert decoded.error == FuzzError.None
  decoded.value
proc fuzzImport*(body: OwnedBlock, limits: FuzzLimits = fuzzProtocolTestLimits()): FuzzMessage =
  ## ImportBlock contains the exact current sealed header and extrinsic bytes.
  var bytes = newSeq[byte](body.blockInfo.value.consumed)
  assert body.encodeOwnedBlock(bytes).error == FrameError.None
  var wire = @[3'u8]
  for octet in bytes: wire.add(octet) # No fixture repair or compatibility translation occurs.
  let decoded = decodeFuzzMessage(wire, limits)
  assert decoded.error == FuzzError.None
  decoded.value
proc fuzzGetState*(header: OwnedHeader, limits: FuzzLimits = fuzzProtocolTestLimits()): FuzzMessage =
  ## State lookup uses the full sealed header identity, independently of its prior-state field.
  var bytes = newSeq[byte](header.headerInfo.value.consumed)
  assert header.encodeOwnedHeader(bytes).error == HeaderError.None
  let hashed = blake2b256(bytes)
  assert hashed.error == CryptoError.None
  var wire = @[4'u8]
  for octet in array[32, byte](hashed.value): wire.add(octet) # Exact request hash remains a header identity.
  let decoded = decodeFuzzMessage(wire, limits)
  assert decoded.error == FuzzError.None
  decoded.value
