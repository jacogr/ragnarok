# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Test-only fuzzer request construction composes exact existing immutable child encodings.
import std/assertions
import ./[fuzz_protocol_context, current_consecutive_context, accumulation_current_chain_context]
import ../../src/app/fuzz_backend
import ../../src/state/[fuzz_protocol, store]
import ../../src/codec/[bounded, header, block_codec]
import ../../src/crypto/primitives
proc fuzzBackendTestConfig*(): FuzzBackendConfig =
  ## Keep the independently frozen current STF profile and explicit resource policies.
  FuzzBackendConfig(parameters: currentChainSettings(), candidate: currentConsecutiveLimits(),
      wire: fuzzProtocolTestLimits())
proc fuzzInitialize*(header: OwnedHeader, state: StateStoreSnapshot): FuzzMessage =
  ## An Initialize contains exact header bytes, a rootless complete map and zero ancestry.
  let limits = fuzzProtocolTestLimits()
  var wire = @[1'u8]
  var head = newSeq[byte](header.headerInfo.value.consumed)
  assert header.encodeOwnedHeader(head).error == HeaderError.None
  for octet in head: wire.add(octet) # Child serialization is unchanged before enclosing composition.
  let serialized = newFuzzState(state, limits).value.copyFuzzMessage(limits.bytes).value
  for index in 1..<serialized.len: wire.add(serialized[
      index]) # Replace only State's discriminant, retaining the rootless map.
  wire.add(0)
  let decoded = decodeFuzzMessage(wire, limits)
  assert decoded.error == FuzzError.None
  decoded.value
proc fuzzImport*(body: OwnedBlock): FuzzMessage =
  ## ImportBlock contains the exact current sealed header and extrinsic bytes.
  var bytes = newSeq[byte](body.blockInfo.value.consumed)
  assert body.encodeOwnedBlock(bytes).error == FrameError.None
  var wire = @[3'u8]
  for octet in bytes: wire.add(octet) # No fixture repair or compatibility translation occurs.
  let decoded = decodeFuzzMessage(wire, fuzzProtocolTestLimits())
  assert decoded.error == FuzzError.None
  decoded.value
proc fuzzGetState*(header: OwnedHeader): FuzzMessage =
  ## State lookup uses the full sealed header identity, independently of its prior-state field.
  var bytes = newSeq[byte](header.headerInfo.value.consumed)
  assert header.encodeOwnedHeader(bytes).error == HeaderError.None
  let hashed = blake2b256(bytes)
  assert hashed.error == CryptoError.None
  var wire = @[4'u8]
  for octet in array[32, byte](hashed.value): wire.add(octet) # Exact request hash remains a header identity.
  let decoded = decodeFuzzMessage(wire, fuzzProtocolTestLimits())
  assert decoded.error == FuzzError.None
  decoded.value
