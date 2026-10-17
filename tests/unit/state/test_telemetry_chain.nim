import std/[assertions, syncio, strutils]
import ../../../src/telemetry/[wire, chain]

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
# Full-profile genesis headers exceed 64 KiB; accept the configured cap and reject one byte beyond it.
let largePrefix = "{\"protocol_parameters\":\"" & parameters & "\",\"genesis_header\":\""
assert chainMetadata(largePrefix & repeat('0', 2 * MaxHeaderBytes) & "\"}", identity, address, 9000).ok
assert not chainMetadata(largePrefix & repeat('0', 2 * (MaxHeaderBytes + 1)) & "\"}", identity,
    address, 9000).ok
echo "telemetry chain ok"
