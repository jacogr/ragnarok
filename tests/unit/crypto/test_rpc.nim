# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise loopback RPC server internals, HTTP upgrade, masked WebSocket frames and JSON-RPC
## response handling.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio, base64]
import ../../../src/chain/[services, statistics, beefy, reports]
from ../../../src/codec/header import OwnedHeader, HeaderError, encodeOwnedHeader, error
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

let upgradeHeader = "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: keep-alive, Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
assert "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" in upgrade(upgradeHeader) # RFC 6455 section 1.3 known answer.
assert upgrade(upgradeHeader.replace("GET /", "POST /")).len == 0
assert upgrade(upgradeHeader.replace("Host: localhost", "Origin : http://example.com")).len == 0
assert upgrade(upgradeHeader.replace("Host: localhost", "Host: local\x00host")).len == 0
assert upgrade(upgradeHeader.replace("13\r\n", "12\r\n")).len == 0
assert upgrade(upgradeHeader.replace("Host: localhost", "Origin: http://example.com")).len == 0
assert upgrade(upgradeHeader.replace("Host: localhost", "Host: a\r\nHost: b")).len == 0
assert upgrade(upgradeHeader.replace("dGhlIHNhbXBsZSBub25jZQ==", "!!!!!!!!!!!!!!!!!!!!!!!!")).len == 0
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
# Independently encoded chapter 13: two six-validator E4 arrays, four core tuples and one service.
let activityHex = "06" & repeat("00000000", 36) & "06" & repeat("00000000", 36) & repeat("00", 32) &
    "012a000000" & repeat("00", 10) & "ff" & repeat("ff", 8)
let activityKey = "0d" & repeat("00", 30)
let previousKey = "09" & repeat("00", 30)
# Build a fresh configured view, preserving independent current and previous roster encodings.
proc activityInfo(wire: string, previous = "06" & repeat("00", 2016)): ClientInfo =
  let state = genesisState[0..^2] & ",\"" & previousKey & "\":\"" & previous & "\",\"" &
      activityKey & "\":\"" & wire & "\"}"
  ClientInfo(genesis: configuredGenesis(genesisText.replace(genesisState, state),
      genesisParameters.value))
let activityCall = "{\"jsonrpc\":\"2.0\",\"method\":\"statistics\",\"params\":[\"" & genesisHash &
    "\"],\"id\":1}"
let activityOwner = activityInfo(activityHex)
let activityAnswer = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"BgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAYAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEqAAAAAAAAAAAAAAAAAP///////////w==\"}"
assert respond(activityCall, activityOwner) == activityAnswer
assert respond("[" & activityCall & "," & activityCall & "]", activityOwner) == "[" &
    activityAnswer & "," & activityAnswer & "]"
assert respond(activityCall.replace(",\"id\":1", ""), activityOwner) == ""
assert "\"statistics\"" in respond(request, activityOwner)
assert "\"code\":0" in respond(activityCall, withGenesis) # Missing chapter is not null or zero statistics.
assert "\"code\":1" in respond(activityCall, info)
assert "\"code\":1" in respond(activityCall.replace(genesisHash, repeat("A", 43) & "="), activityOwner)
for hash in ["x", "", "AB=="]: # Hash syntax is validated before accessing the snapshot.
  assert "\"code\":-32602" in respond(activityCall.replace(genesisHash, hash), activityOwner)
assert "\"code\":-32602" in respond(activityCall.replace("],", ",0],"), activityOwner)
for size in 0..<(activityHex.len div 2): # Every truncated chapter must fail rather than exposing its valid prefix.
  assert "\"code\":0" in respond(activityCall, activityInfo(activityHex[0..<size*2]))
for bad in [activityHex & "00", "05" & activityHex[2..^1], repeat("00", 32769)]:
  assert "\"code\":0" in respond(activityCall, activityInfo(bad)) # Suffix, population mismatch and size policy.
# Reject duplicate service keys and an overlong zero gas encoding in otherwise complete chapters.
let serviceTuple = "2a000000" & repeat("00", 11)
for bad in [activityHex[0..<644] & "02" & serviceTuple & serviceTuple,
    activityHex[0..^19] & "8000"]:
  assert "\"code\":0" in respond(activityCall, activityInfo(bad))
assert "\"code\":0" in respond(activityCall, activityInfo(activityHex, "00"))
assert "\"code\":0" in respond(activityCall, activityInfo(activityHex, "06" & repeat("00", 2016) & "00"))
# Different valid previous populations are accepted only when chapter 13 matches that actual roster.
let resizedHex = activityHex[0..<290] & "09" & repeat("00000000", 54) & activityHex[580..^1]
assert "\"result\"" in respond(activityCall, activityInfo(resizedHex, "09" & repeat("00", 3024)))
assert statistics.statistics(default(Genesis), ByteLimit(32768)).error ==
    StatisticsReadError.Uninitialized
let limitedActivity = statistics.statistics(activityOwner.genesis.value, ByteLimit((
    activityHex.len div 2) - 1))
assert limitedActivity.error == StatisticsReadError.LimitExceeded

# Copies extracted from a retained statistics view cannot mutate its original bytes.
let activityView = statistics.statistics(activityOwner.genesis.value, ByteLimit(32768))
assert activityView.error == StatisticsReadError.None
var activityCopy = activityView.value.bytes
activityCopy[0] = 0
assert activityView.value.bytes[0] == 6
# Repeated decoding and response construction must release roster and statistics temporary owners.
proc retireActivityReply() =
  assert respond(activityCall, activityOwner) == activityAnswer
retireActivityReply()
let activityBaseline = getOccupiedMem()
for iteration in 0..<100: retireActivityReply() # Warm repeated calls must not retain decoder snapshots.
assert getOccupiedMem() <= activityBaseline + 256

# Service discovery excludes malformed accounts and orphan keys already present in the frozen map.
let listCall = "{\"jsonrpc\":\"2.0\",\"method\":\"listServices\",\"params\":[\"" & genesisHash &
    "\"],\"id\":1}"
let listAnswer = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[42,4294967295]}"
assert respond(listCall, serviceInfo) == listAnswer
assert respond(listCall, withGenesis) == "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[]}"
assert "\"code\":1" in respond(listCall, info)
assert "\"code\":1" in respond(listCall.replace(genesisHash, repeat("A", 43) & "="), serviceInfo)
assert respond(listCall.replace(",\"id\":1", ""), serviceInfo) == ""
assert "\"listServices\"" in respond(request, serviceInfo)
assert respond("[" & listCall & "," & listCall & "]", serviceInfo) == "[" & listAnswer & "," &
    listAnswer & "]"
for invalid in [listCall.replace(genesisHash, "bad"), listCall.replace("],", ",0],"),
    listCall.replace("[\"" & genesisHash & "\"]", "[]"), listCall.replace("[\"" & genesisHash &
        "\"]", "{}")]:
  assert "\"code\":-32602" in respond(invalid, serviceInfo) # Exactly one canonical hash is mandatory.
# Independently construct literal C(255, service) keys without the production constructor.
proc accountHex(service: uint32): string =
  result = "ff"
  for shift in 0..<4: result.add(toHex(int64((service shr (shift * 8)) and 255), 2) & "00") # E4 interleaving.
  result.add(repeat("00", 22)) # Complete all fixed zero positions of the 31-byte key.
# Capture one map from supplied account JSON; source buffers may be edited/dropped afterward.
proc discoveryInfo(accounts: string): ClientInfo =
  let state = genesisState[0..^2] & accounts & "}"
  ClientInfo(genesis: configuredGenesis(genesisText.replace(genesisState, state),
      genesisParameters.value))
var accounts = ""
for service in [256'u32, 255'u32, 0'u32, 1'u32]: # Deliberately neither numeric nor serialized-key order.
  accounts.add(",\"" & accountHex(service) & "\":\"" & repeat("00", 89) & "\"")
# Exact key matching rejects near-account keys; exact metadata matching rejects unsupported/extended values.
accounts.add(",\"" & accountHex(2)[0..^3] & "01\":\"" & repeat("00", 89) & "\"")
accounts.add(",\"" & accountHex(3) & "\":\"01" & repeat("00", 88) & "\"")
accounts.add(",\"" & accountHex(4) & "\":\"" & repeat("00", 90) & "\"")
let discovered = discoveryInfo(accounts)
accounts = "" # The retained scalar list cannot alias mutable source text.
assert respond(listCall, discovered) == "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[0,1,255,256]}"
assert discovered.genesis.value.serviceCount == 4
var copiedService = discovered.genesis.value.serviceAt(ServiceListIndex(0))
copiedService = ServiceIndex(123)
assert uint32(discovered.genesis.value.serviceAt(ServiceListIndex(0))) == 0
# A large valid map proves list output is bounded without silently returning an arbitrary prefix.
var manyAccounts = ""
var mediumServices = default(ClientInfo)
for index in 0..<6000:
  manyAccounts.add(",\"" & accountHex(4_000_000_000'u32 + uint32(index)) & "\":\"" & repeat("00",
      89) & "\"")
  if index == 3999: mediumServices = discoveryInfo(
      manyAccounts) # Retain a list that fits alone but not twice.
let mediumBatch = respond("[" & listCall & "," & listCall & "]", mediumServices)
assert mediumBatch.len <= 65535 and "\"result\":[4000000000," in mediumBatch
assert "\"code\":0" in mediumBatch and mediumBatch.split("\"id\":").len == 3
let manyServices = discoveryInfo(manyAccounts)
assert manyServices.genesis.error == GenesisError.None
assert manyServices.genesis.value.serviceCount == 6000
assert "\"code\":0" in respond(listCall, manyServices) # 66,001 result bytes exceed the whole frame budget.
# Mixed blobs and discovery share one aggregate response budget.
let listBatch = "[" & repeat(largeCall & ",", 2) & listCall & "]"
let listBatchReply = respond(listBatch, serviceInfo)
assert listBatchReply.len <= 65535 and "\"result\":[42,4294967295]" in listBatchReply

# Frozen request-key equations and histories are independent of production constructors.
let requestState = serviceState[0..^2] &
  ",\"2a9f000e0044004c69f77a49bd0be89db92c38fe713e0963165cca12faf571\":\"00\"" &
  ",\"2a63002800c3003fb877a13c099c72e17345ca7456b1feef2a17cfe4bc5f67\":\"0100000000\"" &
  ",\"2a2100bb000400dfa224311755a2d9967d43cdd45d586c662d29b555ac253f\":\"0201000000ffffffff\"" &
  ",\"2a41000c008b00bb716d041a883bf3a1f5572a0510f7cd920057800f95d72b\":\"030000000000000080ffffffff\"" &
  ",\"2a5900bd006e0009adaf509d783eea30aa1613a5ca20d67726fd8f22a37edc\":\"00\"" &
  ",\"2a640073006b0036054365dbb54bd49c71e29ce67361fc2cc3ee93e43e9af8\":\"00\"" &
  ",\"2a7300e3001200037a3b50d7edd8c745f2ecf8369e32e20f41345e23189128\":\"04\"" &
  ",\"2a420004008a00a811572c33c69803a3ab3e8bae6796ff8e1304cbd807247e\":\"0000\"" &
  ",\"2ab200540082004f0ab3061e517af2f904bb387ba8e3dccc0381f9a9de0f8f\":\"8000\"" & "}"
let requestsText = genesisText.replace(genesisState, requestState)
let requestsInfo = ClientInfo(genesis: configuredGenesis(requestsText, genesisParameters.value))
# Build four-argument history queries without narrowing unsigned length literals.
proc requestCall(length: string): string =
  serviceCall("serviceRequest", "42", ",\"" & repeat("A", 43) & "=\"," & length)
let histories = ["[]", "[0]", "[1,4294967295]", "[0,2147483648,4294967295]"]
for index in 0..<4: # Empty requested state is distinct from an absent key; timestamps preserve full E4 values.
  assert respond(requestCall($index), requestsInfo) == "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":" &
      histories[index] & "}"
assert "\"result\":null" in respond(requestCall("9"), requestsInfo)
assert "\"result\":[]" in respond(requestCall("4294967293"), requestsInfo)
for length in ["4", "5", "6"]: # Excess count, trailing bytes and overlong count must not become successful histories.
  assert "\"code\":0" in respond(requestCall(length), requestsInfo)
for length in ["4294967294", "4294967295"]: # Present marker keys are ambiguous even if their bytes look like a history.
  assert "Request namespace ambiguous" in respond(requestCall(length), requestsInfo)
  assert "\"result\":null" in respond(requestCall(length).replace(repeat("A", 43) & "=", "AQ" &
      repeat("A", 41) & "="), requestsInfo)
assert "\"result\":null" in respond(requestCall("0").replace(",42,", ",41,"), requestsInfo)
assert "\"code\":0" in respond(requestCall("0").replace(",42,", ",43,"), requestsInfo)
assert "\"code\":1" in respond(requestCall("0"), info)
assert "\"code\":1" in respond(requestCall("0").replace(genesisHash, repeat("A", 43) & "="), requestsInfo)
for length in ["-1", "4294967296", "18446744073709551615", "1.0", "1e0", "true", "null", "\"1\""]:
  assert "\"code\":-32602" in respond(requestCall(length), requestsInfo) # Exact uint32 integer syntax only.
assert "\"code\":-32602" in respond(requestCall("0").replace(repeat("A", 43) & "=", "bad"), requestsInfo)
assert "\"code\":-32602" in respond(requestCall("0").replace("],", ",0],"), requestsInfo)
assert respond(requestCall("0").replace(",\"id\":1", ""), requestsInfo) == ""
let requestsBatch = respond("[" & requestCall("0") & "," & requestCall("1") & "]", requestsInfo)
assert requestsBatch == "[{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[]},{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[0]}]"
let threeSlots = "030000000000000080ffffffff"
for size in 0..<13: # Every incomplete three-slot value fails, including the empty byte string.
  let field = "\"2a41000c008b00bb716d041a883bf3a1f5572a0510f7cd920057800f95d72b\":\""
  let shortened = requestsText.replace(field & threeSlots, field & threeSlots[0..<size*2])
  let invalid = ClientInfo(genesis: configuredGenesis(shortened, genesisParameters.value))
  assert "\"code\":0" in respond(requestCall("3"), invalid)
let defaultRequest = services.serviceRequest(default(Genesis), ServiceIndex(42), default(
    ServicePreimageHash), RequestLength(0))
assert defaultRequest.error == ServiceReadError.Uninitialized
let emptyRequestResult = default(ServiceRequestResult)
assert emptyRequestResult.error == ServiceReadError.Uninitialized

# Excess bytes and repeated extraction cannot expose a partial history or retain temporary request owners.
let longHistoryText = requestsText.replace(threeSlots & "\"", threeSlots & "00\"")
let longHistoryInfo = ClientInfo(genesis: configuredGenesis(longHistoryText,
    genesisParameters.value))
assert "\"code\":0" in respond(requestCall("3"), longHistoryInfo)
proc retireRequestReply() =
  assert "\"result\":[0,2147483648,4294967295]" in respond(requestCall("3"), requestsInfo)
retireRequestReply()
let requestBaseline = getOccupiedMem()
for iteration in 0..<100: retireRequestReply() # Hashing, decoding and rendering release all temporary owners.
assert getOccupiedMem() <= requestBaseline + 256

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

# Independent C(3) bytes bind the newest super-peak to the configured header and slot.
proc beefyInfo(wire: string): ClientInfo =
  ## Capture a fresh immutable configured map with the supplied history bytes.
  let state = genesisState[0..^2] & ",\"03" & repeat("00", 30) & "\":\"" & wire & "\"}"
  ClientInfo(genesis: configuredGenesis(genesisText.replace(genesisState, state),
    genesisParameters.value))
let beefyCall = rootRequest.replace("stateRoot", "beefyRoot")
let historyHeader = "e6638eb23c6a531864cb91d8bf1a26c66feeedd83b55cc2a72c9c35900428ed4"
let historyRecord = historyHeader & repeat("ab", 32) & repeat("00", 32) & "0700000000"
let beefyWire = "01" & historyRecord & "00"
let beefyOwner = beefyInfo(beefyWire)
let beefyAnswer = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"q6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s=\"}"
assert respond(beefyCall, beefyOwner) == beefyAnswer
assert respond("[" & beefyCall & "," & beefyCall & "]", beefyOwner) == "[" & beefyAnswer & "," &
    beefyAnswer & "]"
assert respond(beefyCall.replace(",\"id\":1", ""), beefyOwner) == ""
assert "\"beefyRoot\"" in respond(request, beefyOwner)
assert "\"code\":0" in respond(beefyCall, withGenesis)
assert "\"code\":1" in respond(beefyCall, info)
assert "\"code\":1" in respond(beefyCall.replace(genesisHash, repeat("A", 43) & "="), beefyOwner)
assert "\"code\":-32602" in respond(beefyCall.replace(genesisHash, "bad"), beefyOwner)
# Empty/malformed/suffixed history and a mismatched newest block must never publish a root.
for wire in ["0000", "", "09", beefyWire & "00", beefyWire[0..^3],
    beefyWire.replace(historyHeader, repeat("00", 32)),
    beefyWire.replace("07000000", "08000000")]:
  assert "\"code\":0" in respond(beefyCall, beefyInfo(wire))
# Older records may differ; selection is explicitly the last record, including a legitimate zero root.
assert respond(beefyCall, beefyInfo("02" & historyRecord.replace("ab", "cd") & historyRecord &
    "00")) == beefyAnswer
assert "\"result\":\"" & repeat("A", 43) & "=\"" in respond(beefyCall, beefyInfo(beefyWire.replace(
    "ab", "00")))
assert beefyRoot(default(Genesis)).error == BeefyReadError.Uninitialized
# Reject oversized chapters before copying their untrusted contents.
assert "\"code\":0" in respond(beefyCall, beefyInfo(repeat("00", 262145)))

# Repeated decoding must retire its history owner after copying the fixed reply root.
proc retireBeefyReply() =
  ## Exercise decoder and JSON ownership without retaining the transient history snapshot.
  assert respond(beefyCall, beefyOwner) == beefyAnswer
retireBeefyReply()
let beefyBaseline = getOccupiedMem()
for iteration in 0..<100:
  # Fresh decoder owners must all release their arrays and package/peak storage.
  retireBeefyReply()
assert getOccupiedMem() <= beefyBaseline + 256

# Independent Python report/guarantee oracle fixes exact canonical report bytes and identity.
proc reportInfo(wire: string): ClientInfo =
  ## Capture an immutable chapter-10 fixture without borrowing the source JSON.
  let state = genesisState[0..^2] & ",\"0a" & repeat("00", 30) & "\":\"" & wire & "\"}"
  ClientInfo(genesis: configuredGenesis(genesisText.replace(genesisState, state),
      genesisParameters.value))
let reportWire = "000130466e0ae1b05dde5249872475f6beeac368fd014b5a3413ceb32d38721432842a0000007af11fdaa717c398e223211842b41392f18df4bbc4ea0f4cfb972f19c7a649490600e8e52949f6e4fb1d943248df48c3f2b538200fddfea22388e5e061be8ebf21a74500c0564c5e0de0942589df4343ad1956da66797240e2a2f2d6f8116b50477689860b000000f6967658df626fa39cbfb6014b50196d23bc2cfbfa71a7591ca7715472dd2b489329de635d4bbb8c47cdccbbc1285e48bf9dbad365af44b205343e99dea298f360751ab5b251361fbfd3ad5b0e84f051ccece6b00830aed31a5354e00b20b9ed210000008f665c40573f1288749767417430f62360e37865ef773c24186527aa24b5a4930001022e5e165cc8bd586404257f5cd6f5a31177b5c951eb076c7c10174f90006eef000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffff02000011111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111010012121212121212121212121212121212121212121212121212121212121212121212121212121212121212121212121212121212121212121212121212121212070000000000"
let reportOwner = reportInfo(reportWire)
let reportHashText = "TPewtqai8WQjWIo74eXNrAyVpYAPROxl7JGzk+ASWA0="
let reportCall = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"workReport\",\"params\":[\"" &
    reportHashText & "\"]}"
let reportAnswer = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"MEZuCuGwXd5SSYckdfa+6sNo/QFLWjQTzrMtOHIUMoQqAAAAevEf2qcXw5jiIyEYQrQTkvGN9LvE6g9M+5cvGcemSUkGAOjlKUn25PsdlDJI30jD8rU4IA/d/qIjiOXgYb6OvyGnRQDAVkxeDeCUJYnfQ0OtGVbaZnlyQOKi8tb4EWtQR3aJhgsAAAD2lnZY32Jvo5y/tgFLUBltI7ws+/pxp1kcp3FUct0rSJMp3mNdS7uMR83Mu8EoXki/nbrTZa9EsgU0PpneopjzYHUatbJRNh+/061bDoTwUczs5rAIMK7TGlNU4Asgue0hAAAAj2ZcQFc/Eoh0l2dBdDD2I2DjeGXvdzwkGGUnqiS1pJMAAQIuXhZcyL1YZAQlf1zW9aMRd7XJUesHbHwQF0+QAG7vAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"}"
assert respond(reportCall, reportOwner) == reportAnswer
assert respond("[" & reportCall & "," & reportCall & "]", reportOwner) == "[" & reportAnswer & "," &
    reportAnswer & "]"
assert respond(reportCall.replace(",\"id\":1", ""), reportOwner) == ""
assert "\"workReport\"" in respond(request, reportOwner)
# Absent configuration, chapter and empty assignments all report unavailability with the requested identity.
for owner in [info, withGenesis, reportInfo("00000000")]:
  assert respond(reportCall, owner) == "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":2,\"message\":\"Work-report unavailable\",\"data\":\"" &
      reportHashText & "\"}}"
assert "\"code\":2" in respond(reportCall.replace(reportHashText, repeat("A", 43) & "="), reportOwner)
assert "\"code\":-32602" in respond(reportCall.replace(reportHashText, "bad"), reportOwner)
# Complete parent validation rejects truncation, invalid tags and suffixes even after a matching report.
for wire in ["", "02", reportWire[0..^3], reportWire & "00"]:
  assert "\"code\":0" in respond(reportCall, reportInfo(wire))
# Repeated lookup must retire parent snapshots, report copies and cryptographic temporary buffers.
proc retireReportReply() =
  ## Assert lookup while retaining only the original configured state across calls.
  assert respond(reportCall, reportOwner) == reportAnswer
retireReportReply()
let reportBaseline = getOccupiedMem()
for iteration in 0..<100:
  # Every decoder owner must be retired after the response's copied bytes are released.
  retireReportReply()
assert getOccupiedMem() <= reportBaseline + 256

# The matching report obeys its exact reply allowance; unrelated misses do not consume it.
let reportIdentity = WorkReportHash([76'u8, 247'u8, 176'u8, 182'u8, 166'u8, 162'u8, 241'u8, 100'u8,
    35'u8, 88'u8, 138'u8, 59'u8, 225'u8, 229'u8, 205'u8, 172'u8, 12'u8, 149'u8, 165'u8, 128'u8,
    15'u8, 68'u8, 236'u8, 101'u8, 236'u8, 145'u8, 179'u8, 147'u8, 224'u8, 18'u8, 88'u8, 13'u8])
assert workReport(default(Genesis), reportIdentity, ByteLimit(393)).error ==
    ReportReadError.Uninitialized
assert workReport(reportOwner.genesis.value, reportIdentity, ByteLimit(392)).error ==
    ReportReadError.LimitExceeded
assert workReport(reportOwner.genesis.value, reportIdentity, ByteLimit(393)).error ==
    ReportReadError.None
assert workReport(reportOwner.genesis.value, default(WorkReportHash), ByteLimit(0)).error ==
    ReportReadError.Missing
# A returned report owns its bytes even after the configured map and parent decoder retire.
proc retainedReport(): OwnedReport =
  ## Return just the validated report owner from a short-lived configured state.
  let transient = reportInfo(reportWire)
  let found = workReport(transient.genesis.value, reportIdentity, ByteLimit(393))
  assert found.error == ReportReadError.None
  found.value
let reportRetained = retainedReport()
var reportCopy = newSeq[byte](393)
assert encodeOwnedReport(reportRetained, reportCopy).error == OwnershipError.None
reportCopy[0] = reportCopy[0] xor 255 # Mutating a copied wire buffer cannot alter the owner.
assert encodeOwnedReport(reportRetained, reportCopy).error == OwnershipError.None
assert base64.encode(reportCopy) in reportAnswer
# Parent policy rejects large chapters before allocating decoder owners.
assert "\"code\":0" in respond(reportCall, reportInfo(repeat("00", 1048577)))
# Extra, absent and non-string arguments fail before lookup.
for call in [reportCall.replace("[\"" & reportHashText & "\"]", "[]"),
    reportCall.replace("[\"" & reportHashText & "\"]", "[0]"),
    reportCall.replace("[\"" & reportHashText & "\"]", "[\"" & reportHashText & "\",0]")]:
  assert "\"code\":-32602" in respond(call, reportOwner)

# Independent ready-queue framing has exactly 600 row counts and no outer length prefix.
let readyReportHex = "30466e0ae1b05dde5249872475f6beeac368fd014b5a3413ceb32d38721432842a0000007af11fdaa717c398e223211842b41392f18df4bbc4ea0f4cfb972f19c7a649490600e8e52949f6e4fb1d943248df48c3f2b538200fddfea22388e5e061be8ebf21a74500c0564c5e0de0942589df4343ad1956da66797240e2a2f2d6f8116b50477689860b000000f6967658df626fa39cbfb6014b50196d23bc2cfbfa71a7591ca7715472dd2b489329de635d4bbb8c47cdccbbc1285e48bf9dbad365af44b205343e99dea298f360751ab5b251361fbfd3ad5b0e84f051ccece6b00830aed31a5354e00b20b9ed210000008f665c40573f1288749767417430f62360e37865ef773c24186527aa24b5a4930002022e5e165cc8bd586404257f5cd6f5a31177b5c951eb076c7c10174f90006eef000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
let readyReportHash = "xFVJ93pjaMduU8oqsAhx/ts/IQl3aFgxetYf8dWPqcw="
let readyCall = reportCall.replace(reportHashText, readyReportHash)
let readyAnswer = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"MEZuCuGwXd5SSYckdfa+6sNo/QFLWjQTzrMtOHIUMoQqAAAAevEf2qcXw5jiIyEYQrQTkvGN9LvE6g9M+5cvGcemSUkGAOjlKUn25PsdlDJI30jD8rU4IA/d/qIjiOXgYb6OvyGnRQDAVkxeDeCUJYnfQ0OtGVbaZnlyQOKi8tb4EWtQR3aJhgsAAAD2lnZY32Jvo5y/tgFLUBltI7ws+/pxp1kcp3FUct0rSJMp3mNdS7uMR83Mu8EoXki/nbrTZa9EsgU0PpneopjzYHUatbJRNh+/061bDoTwUczs5rAIMK7TGlNU4Asgue0hAAAAj2ZcQFc/Eoh0l2dBdDD2I2DjeGXvdzwkGGUnqiS1pJMAAgIuXhZcyL1YZAQlf1zW9aMRd7XJUesHbHwQF0+QAG7vAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"}"
proc readyReportInfo(wire: string, assignments = "", largeEpoch = false): ClientInfo =
  ## Retain supplied ready bytes and optional availability under one captured parameter context.
  var state = genesisState[0..^2] & ",\"0e" & repeat("00", 30) & "\":\"" & wire & "\""
  if assignments.len > 0:
    # Optional availability lets tests distinguish a clean miss from a refused first source.
    state.add(",\"0a" & repeat("00", 30) & "\":\"" & assignments & "\"")
  state.add("}")
  let parameters = if largeEpoch: configuredParameters(configText.replace("58020000",
      "01100000")) else: genesisParameters
  ClientInfo(genesis: configuredGenesis(genesisText.replace(genesisState, state), parameters.value))
let readyWire = repeat("00", 599) & "01" & readyReportHex & "01" & repeat("12", 32)
let readyOwner = readyReportInfo(readyWire, reportWire)
assert respond(readyCall, readyOwner) == readyAnswer
assert respond(reportCall, readyOwner) == reportAnswer # Availability success still takes priority.
assert respond(readyCall, readyReportInfo(readyWire)) == readyAnswer # Missing C(10) also falls back.
assert respond(readyCall, readyReportInfo(readyWire, "00000000")) == readyAnswer
assert "\"code\":2" in respond(reportCall, readyReportInfo(readyWire))
assert "\"code\":2" in respond(readyCall, readyReportInfo(repeat("00", 600)))
assert "\"code\":0" in respond(readyCall, readyReportInfo(readyWire, "02")) # Malformed C(10) cannot be masked.
# A C(10) hit need not decode an unrelated malformed C(14) chapter.
assert respond(reportCall, readyReportInfo("ff", reportWire)) == reportAnswer
# All dependency sets and later rows validate before returning an earlier matching report.
for wire in ["", repeat("00", 599), readyWire & "00", readyWire[0..^3],
    "01" & readyReportHex & "00" & repeat("00", 598) & "ff",
    repeat("00", 599) & "01" & readyReportHex & "02" & repeat("12", 64)]:
  assert "\"code\":0" in respond(readyCall, readyReportInfo(wire))
# Multiple rows/items, including duplicates, preserve lookup identity without hashing dependency bytes.
assert respond(readyCall, readyReportInfo("02" & readyReportHex & "00" & readyReportHex & "00" &
    repeat("00", 599))) == readyAnswer
assert respond("[" & reportCall & "," & readyCall & "]", readyOwner) == "[" & reportAnswer & "," &
    readyAnswer & "]"
assert respond(readyCall.replace(",\"id\":1", ""), readyOwner) == ""
let readyIdentity = WorkReportHash([196'u8, 85'u8, 73'u8, 247'u8, 122'u8, 99'u8, 104'u8, 199'u8,
    110'u8, 83'u8, 202'u8, 42'u8, 176'u8, 8'u8, 113'u8, 254'u8, 219'u8, 63'u8, 33'u8, 9'u8, 119'u8,
    104'u8, 88'u8, 49'u8, 122'u8, 214'u8, 31'u8, 241'u8, 213'u8, 143'u8, 169'u8, 204'u8])
assert workReport(readyOwner.genesis.value, readyIdentity, ByteLimit(392)).error ==
    ReportReadError.LimitExceeded
assert workReport(readyOwner.genesis.value, readyIdentity, ByteLimit(393)).error ==
    ReportReadError.None
assert "\"code\":0" in respond(readyCall, readyReportInfo(repeat("00", 1048577)))
assert "\"code\":0" in respond(readyCall, readyReportInfo(repeat("00", 4097), largeEpoch = true))
proc retainReadyReport(): OwnedReport =
  ## Return a child owner beyond both genesis and ready-ring decoder lifetimes.
  let transient = readyReportInfo(readyWire)
  let found = workReport(transient.genesis.value, readyIdentity, ByteLimit(393))
  assert found.error == ReportReadError.None
  found.value
let readyRetained = retainReadyReport()
var readyCopy = newSeq[byte](393)
assert encodeOwnedReport(readyRetained, readyCopy).error == OwnershipError.None
assert base64.encode(readyCopy) in readyAnswer
proc retireReadyReply() =
  ## Decode and release ring rows, dependency storage and report owners on every call.
  assert respond(readyCall, readyOwner) == readyAnswer
retireReadyReply()
let readyBaseline = getOccupiedMem()
for iteration in 0..<100:
  # Only the original configured snapshot remains live between calls.
  retireReadyReply()
assert getOccupiedMem() <= readyBaseline + 256

# The extension addresses the exact 31-byte serialized map key, not a service storage preimage.
let rawTimeKey = "CwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
let rawMissingKey = "/wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
let rawCall = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ragnarok_stateValue\",\"params\":[\"" &
    genesisHash & "\",\"" & rawTimeKey & "\"]}"
let rawAnswer = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"BwAAAA==\"}"
assert respond(rawCall, withGenesis) == rawAnswer
assert respond(rawCall.replace(rawTimeKey, rawMissingKey), withGenesis) == "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}"
assert "\"ragnarok_stateValue\"" in respond(request, withGenesis)
assert respond(rawCall.replace(",\"id\":1", ""), withGenesis) == ""
assert respond("[" & rawCall & "," & rawCall & "]", withGenesis) == "[" & rawAnswer & "," &
    rawAnswer & "]"
# Unknown or absent blocks preserve error 1 and the requested hash.
for owner in [info, withGenesis]:
  let unknownHash = repeat("A", 43) & "="
  assert respond(rawCall.replace(genesisHash, unknownHash), owner) ==
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":1,\"message\":\"Block unavailable\",\"data\":\"" &
      unknownHash & "\"}}"
# Wrong lengths, noncanonical padding, alternate alphabets and malformed argument shapes reject.
for key in ["", "AA==", repeat("A", 43) & "=", rawTimeKey[0..^2], rawTimeKey & "=",
    rawTimeKey.replace("AA==", "AB=="), "_" & rawTimeKey[1..^1]]:
  assert "\"code\":-32602" in respond(rawCall.replace(rawTimeKey, key), withGenesis)
for args in ["[]", "[0,0]", "[\"" & genesisHash & "\"]", "[\"" & genesisHash & "\",[]]",
    "[\"" & genesisHash & "\",\"" & rawTimeKey & "\",0]"]:
  assert "\"code\":-32602" in respond(rawCall.replace("[\"" & genesisHash & "\",\"" & rawTimeKey &
      "\"]", args), withGenesis)
proc rawValueInfo(hex: string): ClientInfo =
  ## Capture opaque bytes at an otherwise absent serialized key; no schema validation is implied.
  let state = genesisState[0..^2] & ",\"ff" & repeat("00", 30) & "\":\"" & hex & "\"}"
  ClientInfo(genesis: configuredGenesis(genesisText.replace(genesisState, state),
      genesisParameters.value))
let rawOpaqueCall = rawCall.replace(rawTimeKey, rawMissingKey)
assert respond(rawOpaqueCall, rawValueInfo("")) == "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"\"}"
assert respond(rawOpaqueCall, rawValueInfo("ff00")) == "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"/wA=\"}"
let rawLarge = rawValueInfo(repeat("78", 32768))
let rawLargeReply = respond(rawOpaqueCall, rawLarge)
assert base64.encode(repeat("x", 32768)) in rawLargeReply
assert "\"code\":0" in respond(rawOpaqueCall, rawValueInfo(repeat("78", 32769)))
let rawBatch = respond("[" & rawOpaqueCall & "," & rawOpaqueCall & "]", rawLarge)
assert rawBatch.len <= 65535 and "\"code\":0" in rawBatch
assert rawLargeReply in rawBatch # A later refusal does not truncate an earlier complete reply.
proc retireRawReply() =
  ## Repeated raw copies and response serialization must release all temporary storage.
  assert respond(rawCall, withGenesis) == rawAnswer
retireRawReply()
let rawBaseline = getOccupiedMem()
for iteration in 0..<100:
  # Retain only the original immutable map between calls.
  retireRawReply()
assert getOccupiedMem() <= rawBaseline + 256

# Fixed independent C(8)/C(11) keys establish bytewise order and exclusive pagination.
let keysRoster = "CAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
let keysBetween = "CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
let keysRequest = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ragnarok_stateKeys\",\"params\":[\"" &
    genesisHash & "\",null,1]}"
let keysFirst = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"keys\":[\"" & keysRoster &
    "\"],\"next\":\"" & keysRoster & "\"}}"
let keysLast = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"keys\":[\"" & rawTimeKey &
    "\"],\"next\":null}}"
let keysEmpty = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"keys\":[],\"next\":null}}"
assert respond(keysRequest, withGenesis) == keysFirst
assert respond(keysRequest.replace("null,1", "\"" & keysRoster & "\",1"), withGenesis) == keysLast
assert respond(keysRequest.replace("null,1", "\"" & keysBetween & "\",1"), withGenesis) == keysLast
assert respond(keysRequest.replace("null,1", "\"" & rawTimeKey & "\",1"), withGenesis) == keysEmpty
assert respond(keysRequest.replace("null,1", "\"" & rawMissingKey & "\",1"), withGenesis) == keysEmpty
assert respond(keysRequest.replace("null,1", "null,2"), withGenesis) ==
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"keys\":[\"" & keysRoster & "\",\"" & rawTimeKey & "\"],\"next\":null}}"
assert "\"ragnarok_stateKeys\"" in respond(request, withGenesis)
assert "\"code\":1" in respond(keysRequest, info)
assert "\"code\":1" in respond(keysRequest.replace(genesisHash, repeat("A", 43) & "="), withGenesis)
assert respond(keysRequest.replace(",\"id\":1", ""), withGenesis) == ""
assert respond("[" & keysRequest & "," & keysRequest & "]", withGenesis) == "[" & keysFirst & "," &
    keysFirst & "]"
# Counts are strict bounded integers; cursors must be null or exact canonical key encodings.
for args in ["null,0", "null,129", "null,-1", "null,1.0", "null,1e0", "null,true", "null,null",
    "null,4294967296", "\"\",1", "false,1", "[],1", "\"AA==\",1",
    "\"" & keysRoster.replace("AA==", "AB==") & "\",1", "null,1,0"]:
  assert "\"code\":-32602" in respond(keysRequest.replace("null,1", args), withGenesis)
# Enumeration includes malformed/empty values; it lists serialized keys without classifying their contents.
assert respond(keysRequest.replace("null,1", "\"" & rawTimeKey & "\",1"), rawValueInfo("")) ==
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"keys\":[\"" & rawMissingKey & "\"],\"next\":null}}"
assert withGenesis.genesis.value.keyCount == 2
var keyCopy = array[31, byte](withGenesis.genesis.value.keyAt(StateKeyIndex(0)))
keyCopy[0] = 0 # Copies cannot mutate the index or its future pagination order.
assert respond(keysRequest, withGenesis) == keysFirst
assert discovered.genesis.value.keyCount == 9 # Malformed account metadata still has a serialized key.
# A maximum page stays bounded; an oversized batch refuses later pages without partial results.
let keysMaximum = keysRequest.replace("null,1", "null,128")
let keysMaximumReply = respond(keysMaximum, manyServices)
assert keysMaximumReply.split("==").len == 130
let keysBatch = respond("[" & repeat(keysMaximum & ",", 15) & keysMaximum & "]", manyServices)
assert keysBatch.len <= 65535 and "\"code\":0" in keysBatch
assert keysMaximumReply in keysBatch
proc retireKeysReply() =
  ## Retain the immutable index while temporary key copies and JSON responses retire.
  assert respond(keysRequest, withGenesis) == keysFirst
retireKeysReply()
let keysBaseline = getOccupiedMem()
for iteration in 0..<100:
  # Pagination performs no state-value copies or retained request allocations.
  retireKeysReply()
assert getOccupiedMem() <= keysBaseline + 256

# Canonical sealed header bytes are independently fixed, including the prior-state root and seal.
let headerCall = rootRequest.replace("stateRoot", "ragnarok_header")
let headerAnswer = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAREREREREREREREREREREREREREREREREREREREREREQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\"}"
assert respond(headerCall, withGenesis) == headerAnswer
assert "\"ragnarok_header\"" in respond(request, withGenesis)
assert respond(headerCall.replace(",\"id\":1", ""), withGenesis) == ""
assert respond("[" & headerCall & "," & headerCall & "]", withGenesis) == "[" & headerAnswer & "," &
    headerAnswer & "]"
assert "\"code\":1" in respond(headerCall, info)
assert "\"code\":1" in respond(headerCall.replace(genesisHash, repeat("A", 43) & "="), withGenesis)
for args in ["[]", "[0]", "[\"bad\"]", "[\"" & genesisHash & "\",0]"]:
  assert "\"code\":-32602" in respond(headerCall.replace("[\"" & genesisHash & "\"]", args), withGenesis)
proc retainedHeader(): OwnedHeader =
  ## Retain the sealed owner after the chainspec text and temporary genesis handle retire.
  var source = genesisText
  let transient = configuredGenesis(source, genesisParameters.value)
  assert transient.error == GenesisError.None
  source = "{}"
  transient.value.header
let headerRetained = retainedHeader()
var headerCopy = newSeq[byte](297)
assert encodeOwnedHeader(headerRetained, headerCopy).error == HeaderError.None
headerCopy[0] = 255 # Caller-owned copies cannot mutate the retained wire or its identity.
assert encodeOwnedHeader(headerRetained, headerCopy).error == HeaderError.None
assert base64.encode(headerCopy) in headerAnswer
# Independently framed winner/offender fields produce exact 32 KiB and one-byte-over valid headers.
proc headerBoundary(epoch: int, offender: bool): tuple[info: ClientInfo, raw: string] =
  ## Author canonical C.2 fields directly; no production header encoder constructs this fixture.
  let tail = if offender: "\x01" & repeat("\x22", 32) else: "\x00"
  let raw = repeat("\x00", 32) & repeat("\x11", 32) & repeat("\x00", 32) & "\x07\x00\x00\x00" &
    "\x00\x01" & repeat("\x00", 33 * epoch) & repeat("\x00", 98) & tail & repeat("\x00", 96)
  var hex = ""
  for octet in raw:
    # Encode fixture bytes for chainspec transport, without interpreting their header fields.
    hex.add(toHex(ord(octet), 2))
  let epochHex = if epoch == 983: "d7030000" else: "d8030000"
  let parameters = configuredParameters(configText.replace("58020000", epochHex))
  let captured = configuredGenesis(genesisText.replace(genesisWire, hex), parameters.value)
  assert captured.error == GenesisError.None
  (ClientInfo(genesis: captured), raw)
let headerAtLimit = headerBoundary(983, true)
let headerOverLimit = headerBoundary(984, false)
assert headerAtLimit.raw.len == 32768 and headerOverLimit.raw.len == 32769
let headerAtCall = headerCall.replace(genesisHash, "mySq+OaXLMWcwsUgqYC9hHko1ZeTOAqdIXolSxhXnuc=")
let headerOverCall = headerCall.replace(genesisHash, "fz39QzIBzV5fdNWXzdW++HdOWDHdhjmNGZhI4w8ZR/g=")
let headerLargeAnswer = respond(headerAtCall, headerAtLimit.info)
assert base64.encode(headerAtLimit.raw) in headerLargeAnswer
assert "\"code\":0" in respond(headerOverCall, headerOverLimit.info)
let headerBatch = respond("[" & headerAtCall & "," & headerAtCall & "]", headerAtLimit.info)
assert headerBatch.len <= 65535 and "\"code\":0" in headerBatch and headerLargeAnswer in headerBatch
proc retireHeaderReply() =
  ## Header response construction must release byte copies and Base64 buffers on each call.
  assert respond(headerCall, withGenesis) == headerAnswer
retireHeaderReply()
let headerBaseline = getOccupiedMem()
for iteration in 0..<100:
  # The retained codec snapshot is the only header owner intentionally kept across calls.
  retireHeaderReply()
assert getOccupiedMem() <= headerBaseline + 256
# Parameters use the retained active roster, not the maximum implied by four cores.
for population in [6, 9, 12]:
  # Exercise the smallest, intermediate and maximum valid active populations for this profile.
  let roster = toHex(population, 2) & repeat("00", population * 336)
  var source = genesisText.replace("06" & repeat("00", 2016), roster)
  let context = configuredGenesis(source, genesisParameters.value)
  assert context.error == GenesisError.None
  assert int(context.value.activeValidators) == population
  source = "{}" # Captured counts survive replacement of the caller's JSON storage.
  let owner = ClientInfo(parameters: genesisParameters, genesis: context)
  let expected = parameterAnswer.replace("\"val_count\":0", "\"val_count\":" & $population)
  assert respond(parameterRequest, owner) == expected
  assert respond("[" & parameterRequest & "," & parameterRequest & "]", owner) ==
    "[" & expected & "," & expected & "]"
  assert respond(parameterRequest.replace(",\"id\":7", ""), owner) == ""
# An invalid/default genesis result must never be extracted for a parameter-only query.
assert respond(parameterRequest, ClientInfo(parameters: configured,
  genesis: invalidGenesis())) == parameterAnswer
assert respond(parameterRequest, configuredInfo) == parameterAnswer

echo "rpc ok"
