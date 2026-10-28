# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise bounded chain-spec metadata extraction, malformed inputs and explicit field
## encoding.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/assertions
import std/syncio
import std/strutils
import ../../../src/telemetry/wire as telemetry_wire
import ../../../src/telemetry/chain as telemetry_chain

# Syntactic metadata fixture deliberately makes no claim of a valid executable genesis state.
var parameters = repeat('0', 244)
parameters[49] = '2'
let prefix = "{\"protocol_parameters\":\"" & parameters & "\",\"genesis_header\":\"00\""
let identity = default(array[32, byte])
let address = default(array[16, byte])
let parsed = chainMetadata(prefix & ",\"genesis_state\":{},\"bootnodes\":[]}", identity, address, 9000)
assert parsed.ok and parsed.value.coreCount == 2
let hello = registration(parsed.value)
# Independent hashlib.blake2b(bytes([0]), digest_size=32) reference fixes the hash algorithm and extent.
let expected = [3'u8, 23, 10, 46, 117, 151, 183, 183, 227, 216, 76, 5, 57, 29, 19, 154,
    98, 177, 87, 231, 135, 134, 216, 192, 130, 242, 157, 207, 76, 17, 19, 20]
# The digest follows E4 frame length, version and 122 parameter bytes.
for i in 0..<32: assert hello[127 + i] == expected[i]
assert hello[207] == 40 and hello[208] == 35 # Advertised port is little endian 9000.
# Missing, duplicate, mistyped, truncated, malformed and oversized fields never publish a snapshot.
for text in ["", "[]", "{}", prefix, prefix & "} trailing", prefix & ",\"genesis_header\":\"00\"}",
    "{\"protocol_parameters\":true,\"genesis_header\":\"00\"}",
    "{\"protocol_parameters\":\"00\",\"genesis_header\":\"00\"}",
    "{\"protocol_parameters\":\"" & parameters & "\",\"genesis_header\":\"0x00\"}",
    "{\"protocol_parameters\":\"" & parameters & "\",\"genesis_header\":\"xz\"}",
    prefix & ",\"extension\":" & repeat('[', 32) & "0" & repeat(']', 32) & "}"]:
  assert not chainMetadata(text, identity, address, 9000).ok
# Exercise every byte in both hex cases through the public chain decoder and inspect copied metadata.
for value in 0..255:
  let upper = toHex(uint8(value))
  for encoded in [upper, upper.toLowerAscii()]:
    var input = parameters
    input[0] = encoded[0]
    input[1] = encoded[1]
    let decoded = chainMetadata("{\"protocol_parameters\":\"" & input &
        "\",\"genesis_header\":\"00\"}", identity, address, 9000)
    assert decoded.ok and registration(decoded.value)[5] == byte(value)
# The standard hex parser's permissive forms must not expand the chain-file grammar.
for encoded in ["", "0", "0x00", "#0", "0_", "_0", "00_0", " 0", "0 ", "gg"]:
  assert not chainMetadata("{\"protocol_parameters\":\"" & parameters &
      "\",\"genesis_header\":\"" & encoded & "\"}", identity, address, 9000).ok

# Full-profile genesis headers exceed 64 KiB; accept the configured cap and reject one byte beyond it.
let largePrefix = "{\"protocol_parameters\":\"" & parameters & "\",\"genesis_header\":\""
assert chainMetadata(largePrefix & repeat('0', 2 * MaxHeaderBytes) & "\"}", identity, address, 9000).ok
assert not chainMetadata(largePrefix & repeat('0', 2 * (MaxHeaderBytes + 1)) & "\"}", identity,
    address, 9000).ok
echo "telemetry chain ok"
