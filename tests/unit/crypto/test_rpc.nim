# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise loopback RPC server internals, HTTP upgrade, masked WebSocket frames and JSON-RPC
## response handling.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio]
import ../../../src/chain/services
include ../../../src/rpc/server

# Construct independently masked client frames; test payloads stay within the medium-length format.
proc masked(payload: string, opcode = 1, final = true): string =
  result = $char((if final: 128 else: 0) or opcode)
  if payload.len < 126: result.add(char(128 or payload.len)) # Canonical short format.
  else:
    result.add(char(254)); result.add(char(payload.len shr 8)); result.add(char(payload.len and 255))
  result.add("abcd")
  for i in 0..<payload.len: result.add(char(ord(payload[i]) xor ord("abcd"[
      i mod 4]))) # Independent mask application.

let info = ClientInfo(uptimeMs: 12, peers: 3, role: "server", port: 19800)
let request = "{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_clientInfo\",\"id\":7}"
let answer = respond(request, info)
assert "\"id\":7" in answer and "\"connectedPeers\":3" in answer and "\"uptimeMs\":12" in answer
assert "\"transport\":\"websocket\"" in answer and "\"bestBlock\":null" in answer
assert respond("{\"jsonrpc\":\"2.0\",\"method\":\"ragnarok_clientInfo\"}", info) == ""
assert respond("[{\"jsonrpc\":\"2.0\",\"method\":\"absent\"}]", info) == ""
assert "\"code\":0" in respond("{\"jsonrpc\":\"2.0\",\"method\":\"bestBlock\",\"id\":null}", info)
assert "-32602" in respond(request.replace("\"id\":7", "\"id\":7,\"params\":{}"), info)
assert "-32602" in respond(request.replace("\"id\":7", "\"id\":7,\"params\":[1]"), info)
assert "\"result\"" in respond(request.replace("\"id\":7", "\"id\":7,\"params\":[]"), info)
assert "-32600" in respond(request.replace("\"id\":7", "\"id\":true"), info)
assert "-32600" in respond(request.replace("\"id\":7", "\"id\":7,\"id\":8"), info)
assert "-32600" in respond("[]", info)
assert "-32600" in respond("true", info)
assert respond("[" & request & ",false]", info).startsWith("[{\"jsonrpc\":")
# Numeric IDs retain their complete lexeme without conversion through a machine integer or float.
for id in ["184467440737095516160", "-0", "1.5", "1e300", "null", "\"a\\\"b\"",
    "\"\\ud83d\\ude00\""]:
  let response = respond(request.replace("7}", id & "}"), info)
  assert "\"result\"" in response and "\"error\"" notin response
# Malformed syntax must fail atomically instead of partially dispatching a request or batch.
for bad in ["", "[1,]", "{1:2}", "{\"x\":1,}", "01", "1.", "+1", "NaN", "1e", "-", "{}{}",
    "\"\\x41\"", "\"\\ud800\"", "\"\\udc00\"", "\"\x01\"", "\"unterminated", request & " trailing"]:
  assert "-32700" in respond(bad, info)
# The pinned stdlib deliberately accepts extensions; RPC keeps strict JSON at this boundary.
for bad in ["/* comment */" & request, request & "// comment", "[1, \n]", "{\"x\":1, \t}",
    "{true:2}", "{null:2}", "{[]:2}", "{{}:2}", ".1", "-.1", "1.e2", "1e+", "00", "-01",
    "'single quotes'", "\"\\v\"", "\"\\'\"", "\"\\uZZZZ\"", "\"\\ud800\\u0041\"",
    "\"\\ud800\\ud800\"", "\"\\u12\"", "\x00" & request, request & "\x00",
    "\v" & request, "\f" & request, "[]{}", "{}true", "[1 2]", "{\"x\" 1}",
    "{\"x\":}", "[", "{", "{\"x\":1", "[1"]:
  assert "-32700" in respond(bad, info) # Each extension/error must fail before dispatch.
# Valid escapes, JSON whitespace and nested extension fields remain accepted by standard decoding.
for id in ["184467440737095516160", "-0", "1.50e+003", "1e9999"]:
  assert "\"id\":" & id & "," in respond(request.replace("7}", id & "}"), info)
for id in ["\"\\u0000\"", "\"\\u0022\"", "\"\\u005c\"", "\"\\/\\b\\f\\n\\r\\t\"",
    "\"/* literal comment */ ,] .1\""]:
  assert "\"result\"" in respond(request.replace("7}", id & "}"), info)
assert "\"result\"" in respond(" \t\r\n" & request & " \r\n", info)
assert "\"result\"" in respond(request.replace("7}", "7,\"extra\":{\"a\":[{},[],1]}}"), info)
# Empty containers at depth 15 fit; a scalar at depth 16 and the 2049th value exceed policy.
assert "-32600" in respond(repeat("[", 16) & repeat("]", 16), info)
assert "-32700" in respond(repeat("[", 16) & "0" & repeat("]", 16), info)
assert "-32600" in respond("[" & repeat("0,", 2046) & "0]", info)
assert "-32700" in respond("[" & repeat("0,", 2047) & "0]", info)
assert "-32700" in respond(repeat("[", 18) & "0" & repeat("]", 18), info)
assert "-32700" in respond(repeat(" ", MaxMessage + 1), info)
assert "-32600" in respond("[" & repeat(request & ",", 16) & request & "]", info)
assert validUtf8("\xf0\x9f\x98\x80")
for bad in ["\xc0\xaf", "\xed\xa0\x80", "\xf4\x90\x80\x80", "\x80", "\xe2\x82"]:
  assert not validUtf8(bad) # Reject overlong, surrogate, out-of-range and truncated scalars.

# Literal independent field values exercise all 29 offsets/widths, including an unsigned 64-bit maximum.
const ParameterHex = "ffffffffffffffff02000000000000000300000000000000040005000000580200000700000000000000080000000000000009000000000000000a000000000000000b000c000d000e000f000000100011001200130014001500160000001700000018000000190000001a0000001b0000001c000000f4010000"
const ParameterJson = "{\"V1\":{\"deposit_per_item\":18446744073709551615,\"deposit_per_byte\":2,\"deposit_per_account\":3,\"core_count\":4,\"min_turnaround_period\":5,\"epoch_period\":600,\"max_accumulate_gas\":7,\"max_is_authorized_gas\":8,\"max_refine_gas\":9,\"block_gas_limit\":10,\"recent_block_count\":11,\"max_work_items\":12,\"max_dependencies\":13,\"max_tickets_per_block\":14,\"max_lookup_anchor_age\":15,\"auth_window\":16,\"slot_period_sec\":17,\"auth_queue_len\":18,\"rotation_period\":19,\"max_extrinsics\":20,\"availability_timeout\":21,\"max_authorizer_code_size\":22,\"max_input\":23,\"max_service_code_size\":24,\"max_imports\":25,\"max_report_elective_data\":26,\"transfer_memo_size\":27,\"max_exports\":28,\"epoch_tail_start\":500,\"tickets_attempts_number\":0,\"val_count\":0,\"basic_piece_len\":0,\"segment_piece_count\":0}}"
let configText = "{\"protocol_parameters\":\"" & ParameterHex & "\"}"
let configured = configuredParameters(configText)
assert configured.ok
assert configured.value.get(depositPerItem) == high(uint64)
assert configured.value.get(coreCount) == 4 and configured.value.get(epochTailStart) == 500
var configuredInfo = info
configuredInfo.parameters = configured
let parameterRequest = "{\"jsonrpc\":\"2.0\",\"method\":\"parameters\",\"params\":[],\"id\":7}"
let parameterAnswer = "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":" & ParameterJson & "}"
assert respond(parameterRequest, configuredInfo) == parameterAnswer
assert respond(parameterRequest.replace(",\"params\":[]", ""), configuredInfo) == parameterAnswer
assert "\"code\":0," in respond(parameterRequest, info) # No chain means unavailable, not all-zero settings.
assert "-32602" in respond(parameterRequest.replace("[]", "[1]"), configuredInfo)
assert "-32602" in respond(parameterRequest.replace("[]", "{}"), configuredInfo)
assert respond(parameterRequest.replace(",\"id\":7", ""), configuredInfo) == ""
assert respond("[" & parameterRequest & "," & parameterRequest & "]", configuredInfo) ==
  "[" & parameterAnswer & "," & parameterAnswer & "]"
assert "\"parameters\"" in respond(request, configuredInfo)
let noParameters = default(ParameterResult)
assert not noParameters.ok
for size in 0..<ParameterBytes: # Every truncated tuple must fail before publishing fields.
  assert not decodeParameters(newSeq[byte](size)).ok
assert not decodeParameters(newSeq[byte](ParameterBytes + 1)).ok
assert not decodeParametersHex(repeat("0", ParameterBytes * 2)).ok # Zero clocks and population are unusable.
assert configuredParameters(configText.replace(ParameterHex, ParameterHex.toUpperAscii())).ok
for bad in ["{}", "[]", "null", configText & "{}", configText & "/*x*/",
    "{\"protocol_parameters\":null}", "{\"protocol_parameters\":12}",
    configText.replace("}", ",\"protocol_parameters\":\"" & ParameterHex & "\"}"),
    configText.replace("}", ",\"extra\":1,\"extra\":2}"),
    configText.replace(ParameterHex, ParameterHex[0..^2]),
    configText.replace(ParameterHex, "gg" & ParameterHex[2..^1]),
    configText.replace(ParameterHex, "0x" & ParameterHex),
    configText.replace(ParameterHex, repeat("0", ParameterBytes * 2))]:
  assert not configuredParameters(bad).ok # Invalid syntax, missing/duplicate fields and malformed bytes fail closed.
# Startup parsing has its own finite budget, independent of the smaller per-message RPC limit.
assert not configuredParameters(repeat(" ", 8 * 1024 * 1024 + 1)).ok
assert not configuredParameters("{\"protocol_parameters\":\"" & ParameterHex &
  "\",\"extra\":" & repeat("[", 33) & "0" & repeat("]", 33) & "}").ok
# Mutating borrowed source storage cannot change a previously decoded startup snapshot.
var parameterBytes = default(array[ParameterBytes, byte])
parameterBytes[24] = 2; parameterBytes[30] = 10; parameterBytes[80] = 6; parameterBytes[84] = 1
let retained = decodeParameters(parameterBytes)
assert retained.ok
parameterBytes[24] = 9
assert retained.value.get(coreCount) == 2
parameterBytes[30] = 0
assert not decodeParameters(parameterBytes).ok
parameterBytes[30] = 10; parameterBytes[118] = 11
assert not decodeParameters(parameterBytes).ok # Epoch tail cannot follow the epoch it belongs to.

# A canonical synthetic genesis proves header identity and posterior-root selection independently.
let genesisWire = repeat("00", 32) & repeat("11", 32) & repeat("00", 32) & "07000000" & repeat("00", 197)
let rosterKey = "08" & repeat("00", 30)
let timeKey = "0b" & repeat("00", 30)
let genesisState = "{\"" & rosterKey & "\":\"06" & repeat("00", 2016) & "\",\"" & timeKey &
    "\":\"07000000\"}"
let genesisText = "{\"genesis_header\":\"" & genesisWire & "\",\"genesis_state\":" & genesisState & "}"
let genesisParameters = configuredParameters(configText)
assert genesisParameters.ok
var genesisInput = genesisText
let capturedGenesis = configuredGenesis(genesisInput, genesisParameters.value)
assert capturedGenesis.error == GenesisError.None
genesisInput = "{}" # Mutating source JSON cannot alter the retained owner.
let withGenesis = ClientInfo(genesis: capturedGenesis)
let bestRequest = "{\"jsonrpc\":\"2.0\",\"method\":\"bestBlock\",\"id\":1}"
let genesisHash = "5mOOsjxqUxhky5HYvxomxm/u7dg7VcwqcsnDWQBCjtQ="
let rootRequest = "{\"jsonrpc\":\"2.0\",\"method\":\"stateRoot\",\"params\":[\"" & genesisHash & "\"],\"id\":1}"
assert respond(bestRequest, withGenesis) == "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"header_hash\":\"" &
    genesisHash & "\",\"slot\":7}}"
assert respond(rootRequest, withGenesis) == "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"63T8fX9zxm7i2b5I3Rx0CW41FSpcc9m2rVlS8AK2/Cw=\"}"
assert "\"code\":1" in respond(rootRequest.replace("stateRoot", "parent"), withGenesis)
assert "\"data\":\"" & genesisHash & "\"" in respond(rootRequest, info)
assert "\"code\":1" in respond(rootRequest.replace(genesisHash, repeat("A", 43) & "="), withGenesis)
assert "\"code\":-32602" in respond(rootRequest.replace(genesisHash, "bad"), withGenesis)
assert "\"code\":-32602" in respond(rootRequest.replace("[\"" & genesisHash & "\"]", "[]"), withGenesis)
assert "\"code\":-32602" in respond(bestRequest.replace("\"id\":1", "\"id\":1,\"params\":[0]"), withGenesis)
assert respond(bestRequest.replace(",\"id\":1", ""), withGenesis) == ""
assert "\"code\":-32601" in respond(bestRequest.replace("bestBlock", "finalizedBlock"), withGenesis)
# An absent pair preserves parameter-only operation; every incomplete/malformed pair fails atomically.
assert configuredGenesis("{}", genesisParameters.value).error == GenesisError.Unavailable
for malformed in ["{\"genesis_header\":\"00\"}", "{\"genesis_state\":{}}",
    genesisText.replace(genesisWire, genesisWire & "00"), genesisText.replace(genesisWire,
        genesisWire[0..^3]),
    genesisText.replace(genesisWire, genesisWire.replace("07000000", "08000000")),
        genesisText.replace(genesisState, "{}"),
    genesisText.replace(rosterKey, "bad"), genesisText.replace("\"07000000\"", "null"),
    genesisText.replace("\"07000000\"", "\"0g000000\""),
    genesisText.replace(genesisState, genesisState[0..^2] & ",\"" & timeKey.toUpperAscii &
        "\":\"07000000\"}")]:
  assert configuredGenesis(malformed, genesisParameters.value).error == GenesisError.Invalid

# Independently frozen namespace keys exercise metadata, storage, preimages, and malformed imported state.
let serviceState = genesisState[0..^2] &
  ",\"ff2a0000000000000000000000000000000000000000000000000000000000\":\"" &
      "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" &
          "\"" &
  ",\"ffff00ff00ff00ff0000000000000000000000000000000000000000000000\":\"" &
      "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" &
          "\"" &
  ",\"ff2b0000000000000000000000000000000000000000000000000000000000\":\"" & "01" & "\"" &
  ",\"2a4400fe00350040f10d6e55e19ac2da6b7f208e390f292a3f3b1daf21ce82\":\"" &
      "68656c6c6f00776f726c64" & "\"" &
  ",\"2ac700b000d1003d60856218bc53f8a730be41f3e0ca895ca65b8500a73ea1\":\"" & "" & "\"" &
  ",\"2a4600e90042008b4cc57e8c48ee2ad112bfd563cfe0143d1a773c5706bc54\":\"" & repeat("78", 32768) & "\"" &
  ",\"2a5400eb00030039fae3ad6646f2c9a060bb0896d952f342cecb8cc0e3f125\":\"" & repeat("78", 32769) & "\"" &
  ",\"2a790044009500d39af1592c318e35ea9440a3c490ad7255bafb559c3205e8\":\"" & "707265696d61676500" & "\"" &
  ",\"2aff00f8002900a9ef80195a1da55d802eb8bb02c8606ab3e4f4ed33e3f907\":\"" & "" & "\"" &
  ",\"2a04001d00c5003d2ee85f79cf32bf11fa15bbac7cebf6c9d830191fc76175\":\"" & "77726f6e67" & "\"" &
  ",\"2c4400fe00350040f10d6e55e19ac2da6b7f208e390f292a3f3b1daf21ce82\":\"" & "6f727068616e" & "\"" & "}"
let serviceText = genesisText.replace(genesisState, serviceState)
let serviceGenesis = configuredGenesis(serviceText, genesisParameters.value)
assert serviceGenesis.error == GenesisError.None
let serviceInfo = ClientInfo(genesis: serviceGenesis)
# Produce ordinary positional calls while keeping expected payloads independent of production codecs.
proc serviceCall(methodName, service, extra: string): string =
  "{\"jsonrpc\":\"2.0\",\"method\":\"" & methodName & "\",\"params\":[\"" & genesisHash & "\"," &
      service & extra & "],\"id\":1}"
let dataCall = serviceCall("serviceData", "42", "")
let valueCall = serviceCall("serviceValue", "42", ",\"a2V5\"")
let preimageCall = serviceCall("servicePreimage", "42",
    ",\"ozvvs2aASJ8rCJyozanvt6/zrATgh54DpzsAAMMnzOQ=\"")
assert respond(dataCall, serviceInfo) == "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\"}"
assert respond(valueCall, serviceInfo) == "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"aGVsbG8Ad29ybGQ=\"}"
assert respond(preimageCall, serviceInfo) == "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"cHJlaW1hZ2UA\"}"
assert "\"result\":\"\"" in respond(serviceCall("serviceValue", "42", ",\"\""), serviceInfo)
assert "\"result\":\"\"" in respond(serviceCall("servicePreimage", "42",
    ",\"DldRwCblQ7Loqy6wYJnaodHl30d3j3eH+qtFzfEv46g=\""), serviceInfo)
assert "\"result\":null" in respond(serviceCall("serviceData", "41", ""), serviceInfo)
assert "\"result\":null" in respond(serviceCall("serviceValue", "42", ",\"bm9uZQ==\""), serviceInfo)
assert "\"result\":null" in respond(serviceCall("serviceValue", "44", ",\"a2V5\""), serviceInfo)
assert "\"result\"" in respond(serviceCall("serviceData", "4294967295", ""), serviceInfo)
assert "\"code\":0" in respond(serviceCall("serviceData", "43", ""), serviceInfo)
assert "\"code\":0" in respond(serviceCall("servicePreimage", "42", ",\"" & repeat("A", 43) &
    "=\""), serviceInfo)
assert "\"code\":1" in respond(dataCall, info)
assert "\"code\":1" in respond(dataCall.replace(genesisHash, repeat("A", 43) & "="), serviceInfo)
# Service IDs cannot narrow/wrap or pass through floating-point conversion.
for number in ["-1", "4294967296", "18446744073709551615", "1.0", "1e0", "true", "null", "\"42\""]:
  assert "\"code\":-32602" in respond(serviceCall("serviceData", number, ""), serviceInfo)
# Reject malformed Base64, nonzero padding bits, unknown alphabets, and oversized raw keys.
for key in ["a", "a===", "a2V5=", "AB==", "a2V_", repeat("eA==", 2), repeat("A", 5464)]:
  assert "\"code\":-32602" in respond(serviceCall("serviceValue", "42", ",\"" & key & "\""), serviceInfo)
assert "\"code\":-32602" in respond(serviceCall("serviceData", "42", ",0"), serviceInfo)
assert respond(dataCall.replace(",\"id\":1", ""), serviceInfo) == ""
let largeCall = serviceCall("serviceValue", "42", ",\"bGFyZ2U=\"")
assert respond(largeCall, serviceInfo).len > 43000
assert "\"code\":0" in respond(serviceCall("serviceValue", "42", ",\"b3ZlcnNpemU=\""), serviceInfo)
# Escaped IDs expand on output; reserve their actual encoded sizes before any large result is admitted.
let bigIdCall = largeCall.replace("\"id\":1", "\"id\":\"" & repeat("\\n", 200) & "\"")
let batchAnswer = respond("[" & repeat(bigIdCall & ",", 15) & bigIdCall & "]", serviceInfo)
assert batchAnswer.len <= 65535 and batchAnswer.split("\"id\":").len == 17
assert "\"code\":0" in batchAnswer and "\"result\"" in batchAnswer
# Retained read views survive caller edits to independent extracted byte copies.
assert services.serviceData(default(Genesis), ServiceIndex(42), ByteLimit(89)).error ==
    ServiceReadError.Uninitialized
let readMetadata = services.serviceData(serviceGenesis.value, ServiceIndex(42), ByteLimit(89))
assert readMetadata.error == ServiceReadError.None
var extracted = readMetadata.value.bytes
extracted[0] = 99
assert readMetadata.value.bytes[0] == 0

let header = "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: keep-alive, Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
assert "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" in upgrade(header) # RFC 6455 section 1.3 known answer.
assert upgrade(header.replace("GET /", "POST /")).len == 0
assert upgrade(header.replace("Host: localhost", "Origin : http://example.com")).len == 0
assert upgrade(header.replace("Host: localhost", "Host: local\x00host")).len == 0
assert upgrade(header.replace("13\r\n", "12\r\n")).len == 0
assert upgrade(header.replace("Host: localhost", "Origin: http://example.com")).len == 0
assert upgrade(header.replace("Host: localhost", "Host: a\r\nHost: b")).len == 0
assert upgrade(header.replace("dGhlIHNhbXBsZSBub25jZQ==", "!!!!!!!!!!!!!!!!!!!!!!!!")).len == 0
let encoded = masked(request)
# Every proper prefix is incomplete and has no success-only payload or consumption fields.
for n in 0..<encoded.len: assert decodeFrame(encoded[0..<n]).status == incomplete
let decoded = decodeFrame(encoded)
assert decoded.status == complete
assert decoded.payload == request and decoded.consumed == encoded.len and decoded.final
assert decodeFrame(frame(request)).status == invalid # Clients must mask, servers must not.
assert decodeFrame(masked("x", 3)).status == invalid
assert decodeFrame(masked("x", 9, false)).status == invalid
assert decodeFrame(masked(repeat("x", 126), 9)).status == invalid
assert decodeFrame("\x81\xfe\x00\x01abcdx").status == invalid
assert decodeFrame("\x81\xff").status == invalid
let large = decodeFrame(masked(repeat("x", MaxMessage)))
assert large.status == complete and large.payload.len == MaxMessage
assert decodeFrame(masked(repeat("x", MaxMessage + 1))).status == invalid

# Direct session processing exercises fragmentation and control interleaving without nondeterministic timing.
var slot = default(Connection)
slot.upgraded = true
slot.input = masked(request[0..<20], 1, false)
slot.process(info, 0)
assert slot.fragmented and slot.output.len == 0
slot.input = masked("hello", 9)
slot.process(info, 1)
assert slot.output == frame("hello", 10)
slot.output = ""
slot.input = masked(request[20..^1], 0)
slot.process(info, 2)
assert not slot.fragmented and slot.output == frame(answer)
slot.output = ""
slot.input = masked("", 0)
slot.process(info, 3)
assert slot.closing and slot.output == frame("\x03\xea", 8)
# Disabled and default native owners are safe to tick, close repeatedly and destroy.
var server = default(Server)
assert server.start(0, "server")
server.tick(0)
server.close(); server.close()
# Probe custom-destructor lowering with owned strings even when explicit close is never called.
proc retireBuffers() =
  var owner = default(Server)
  owner.role = repeat("r", 128)
  for slot in mitems(owner.connections): # No sockets are opened; only ARC storage needs retirement.
    slot.input = repeat("i", 1024)
    slot.output = repeat("o", 1024)
    slot.message = repeat("m", 1024)
retireBuffers() # Warm fixed allocator bookkeeping before measuring retained application bytes.
let baseline = getOccupiedMem()
for iteration in 0..<100: retireBuffers() # Repeated custom destruction must not retain nested slot strings.
assert getOccupiedMem() <= baseline + 256
# A newly imported snapshot must retire with the server, even without explicit shutdown.
proc retireGenesis() =
  var owner = default(Server)
  owner.genesis = configuredGenesis(serviceText, genesisParameters.value)
  assert owner.genesis.error == GenesisError.None
retireGenesis() # Warm parsing and trie allocation before measuring retained storage.
let genesisBaseline = getOccupiedMem()
for iteration in 0..<20: retireGenesis() # Independent maps expose a missing custom-destructor field release.
assert getOccupiedMem() <= genesisBaseline + 256
echo "rpc ok"
