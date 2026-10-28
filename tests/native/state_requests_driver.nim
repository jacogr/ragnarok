# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent tagged source histories and fixed-copy observations for service request entries.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/assertions
import std/cmdline
import std/syncio
import std/strutils
import std/parseutils
import ../../src/codec/state_requests as codec_state_requests
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/bounded as codec_bounded

## Preserve malformed empty input without inserting a valid empty-history count.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty trusted token differs from protocol requested-mode zero.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Trusted fixture transport has exactly two lowercase hexadecimal digits per byte.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Reject malformed or partial parses before preserving raw count/timestamp/hash octets.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

## Display complete fixed keys/raw history bytes without manufacturing expected framing.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Trusted transport always needs one token per logical field.
  result = ""
  # Display all fixed octets, preserving leading zeroes.
  for b in bytes: result.add(toHex(int(b), 2).toLowerAscii()) # Leading zeroes matter in fixed E4 fields and hashes.

## Require a complete trusted uint64 token through the supported nonthrowing interface.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number

## Construct the exact supported source alternative from decimal fields, without production decoding.
proc history(parts: seq[string]): RequestHistory =
  let count = unsigned(parts[7])
  assert count <= 3 and parts.len == 8+int(count)
  case count
  of 0: requestedHistory() # No nonexistent timestamp field.
  of 1: availableHistory(RequestSlot(unsigned(parts[8]))) # One supplied-at value.
  of 2: unavailableHistory(RequestSlot(unsigned(parts[8])), RequestSlot(unsigned(parts[
      9]))) # Preserve sequence order.
  else: reavailableHistory(RequestSlot(unsigned(parts[8])), RequestSlot(unsigned(parts[9])),
      RequestSlot(unsigned(parts[10]))) # The trusted count is exactly three.

## Observe only actual active fields, never production re-encoded answers or unused default slots.
proc observed(value: RequestHistoryRead): string =
  result = $value.consumed & " " & $ord(value.history.state)
  case value.history.state
  of RequestState.Requested: discard # Requested mode publishes no timestamp values.
  of RequestState.Available: result.add(" " & $uint32(value.history.since)) # One active availability time.
  of RequestState.Unavailable: result.add(" " & $uint32(value.history.availableFrom) & " " &
      $uint32(value.history.unavailableFrom)) # Preserve both original positions.
  of RequestState.Reavailable: result.add(" " & $uint32(value.history.originalFrom) & " " & $uint32(
      value.history.removedAt) & " " & $uint32(value.history.restoredAt)) # No chronology inference.

## Execute one raw decode or independent typed-source entry request.
proc request(parts: seq[string]) =
  if parts[0] == "D":
    let config = RequestHistoryConfig(items: ElementLimit(unsigned(parts[1])),
        maxBytes: ByteLimit(unsigned(parts[2])))
    var input = unhex(parts[3])
    let parsed = decodeRequestHistory(input, config)
    if parsed.error != RequestError.None:
      echo ($parsed.error).toLowerAscii() # No default requested history or partial consumed extent on failure.
    else:
      for i in 0..<input.len: input[i] = 0 # Returned fixed tagged fields must survive input destruction.
      echo observed(parsed.value)
  else:
    assert parts[0] == "V" or parts[0] == "R" # Trusted operations select entry bytes or one partial root.
    let config = RequestEntryConfig(keyBytes: ByteLimit(unsigned(parts[1])),
        history: RequestHistoryConfig(
      items: ElementLimit(unsigned(parts[2])), maxBytes: ByteLimit(unsigned(parts[3]))))
    let service = ServiceIndex(unsigned(parts[4]))
    var bytes = unhex(parts[5])
    assert bytes.len == 32
    var hash = default(array[32, byte])
    for i in 0..<32: hash[i] = bytes[i] # Literal fixed hash source, separate from stored key construction.
    var value = history(parts)
    let encoded = serviceRequestEntry(service, ServicePreimageHash(hash), RequestLength(
        unsigned(parts[6])), value, config)
    if encoded.error != RequestError.None:
      echo ($encoded.error).toLowerAscii() # No fabricated default key/value after history/key policy failure.
    else:
      value = default(RequestHistory)
      for i in 0..<bytes.len: bytes[i] = 0 # Fresh output cannot depend on the source hash buffer or tagged value.
      hash = default(array[32, byte])
      if parts[0] == "V":
        echo hex(array[31, byte](encoded.value.key)) & " " & hex(encoded.value.value)
      else:
        let root = stateTrieRoot([encoded.value], StateTrieLimits(items: ElementLimit(1),
            perValue: ByteLimit(high(uint64)),
          totalValueBytes: ByteLimit(high(uint64)), nodes: TrieNodeLimit(
              1))) # One request entry, not whole-service or JAM state.
        assert root.error == StateTrieError.None
        echo hex(array[32, byte](root.value.root))

# Each request releases caller buffers independently; decoded histories require no retained heap owner.
for line in lines(paramStr(1)):
  if line.len > 0: request(line.splitWhitespace()) # Empty trusted transport lines contain no operation.
