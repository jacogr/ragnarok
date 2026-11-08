# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## JIP-4 registration projects bounded operator network identity into owned telemetry fields.
## It does not validate or initialize a canonical state snapshot.

import ../chain/network_identity
import ./wire

const
  MaxChainBytes* = MaxNetworkChainBytes   ## Preserve the existing telemetry input ceiling.
  MaxHeaderBytes* = MaxNetworkHeaderBytes ## Preserve the full-profile marker allowance.

proc chainMetadata*(text: string, identity: array[32, byte], address: array[16, byte],
    port: uint16): MetadataResult =
  ## Share exact header identity with JAM ALPN without requiring complete genesis state.
  let parsed = readNetworkIdentity(text)
  if parsed.error != NetworkIdentityError.None:
    return invalidMetadata(if parsed.error == NetworkIdentityError.HashFailed: hashFailed else: invalidChain)
  let params = parsed.value.parametersBytes
  let hash = array[32, byte](parsed.value.genesisHash)
  var bytes = default(array[MetadataSize, byte])
  # Copy exact fetch bytes; the later metadata constructor validates the bounded core count.
  for i in 0..<122: bytes[i] = params[i]
  # Header identity is Blake2b-256 of the complete serialized header, not a state root.
  for i in 0..<32:
    bytes[122 + i] = hash[i]
    bytes[154 + i] = identity[i]
  # Advertise the local QUIC endpoint, never the collector's TCP endpoint.
  for i in 0..<16: bytes[186 + i] = address[i]
  bytes[202] = byte(port and 255)
  bytes[203] = byte(port shr 8)
  metadata(bytes)
