# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted source/observation adapter for independent authorization state equations.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import std/parseutils
import ../../src/codec/state_authorization as codec_state_authorization
import ../../src/codec/state_trie as codec_state_trie
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/assurances as codec_assurances

## Keep an empty byte source expressible as a single transport token.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty pools and malformed empty wire are distinct trusted inputs.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Preserve exact octet order rather than parsing identities as host integers.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Trusted transport contains exactly two lowercase hexadecimal digits per byte.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

## Observe full raw bytes, including leading zeroes and empty source rows.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Preserve empty row boundaries in observed output.
  result = ""
  # Each source hash keeps its exact 32-octet identity.
  for b in bytes: result.add(toHex(int(b), 2).toLowerAscii())

## Build independent typed source rows directly from authored fixed bytes, never production decoder output.
proc rows(parts: seq[string]): seq[AuthorizerRow] {.raises.} =
  let count = parseInt(parts[5])
  assert parts.len == 6+count
  result = newSeq[AuthorizerRow](count)
  # Row lengths are deliberately independent of protocol shape, permitting invalid source tests.
  for i in 0..<count:
    let bytes = unhex(parts[6+i])
    assert bytes.len mod 32 == 0
    result[i] = newSeq[AuthorizerHash](bytes.len div 32)
    # Fixed identity fields are copied from the trusted source schema.
    for j in 0..<result[i].len:
      for k in 0..<32: result[i][j].bytes[k] = bytes[j*32+k] # Preserve per-core position and full bytes.

# Parse full-width unsigned fixture values without narrowing through signed host integers.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number

## Trusted policy values become distinct chain cardinality, aggregate hashes and byte ceilings.
proc config(parts: seq[string]): AuthorizationConfig =
  AuthorizationConfig(cores: CoreCount(unsigned(parts[2])),
    maxHashes: ElementLimit(unsigned(parts[3])), maxBytes: ByteLimit(unsigned(parts[4])))

## Select complete successes and observe immutable snapshots only after caller/source destruction.
proc request(parts: seq[string]) {.raises.} =
  let kind = AuthorizationKind(parseInt(parts[1]))
  let policy = config(parts)
  case parts[0]
  of "V", "R":
    # Independently constructed source arrays exercise entry encoding, not a decoder/encoder round trip.
    var source = rows(parts)
    let encoded = authorizationEntry(kind, source, policy)
    if encoded.error != AuthorizationError.None:
      echo ($encoded.error).toLowerAscii() # Failure exposes no entry/default payload.
    else:
      if parts[0] == "V":
        # Mutation of every source field after encoding must leave the entry unchanged.
        for i in 0..<source.len:
          for j in 0..<source[i].len: source[i][j] = default(AuthorizerHash) # No mutable row storage is retained.
        echo hex(array[31, byte](encoded.value.key)) & " " & hex(encoded.value.value)
      else:
        # Partial integration commits both chapters, using a separate deterministic fixed queue source.
        assert kind == AuthorizationKind.Pools
        var queues = newSeq[AuthorizerRow](source.len)
        # Every queue position gets distinct patterned source bytes, preserving core/position order.
        for i in 0..<queues.len:
          queues[i] = newSeq[AuthorizerHash](80)
          for j in 0..<80:
            for k in 0..<32: queues[i][j].bytes[k] = byte((
                i+j+k) mod 256) # Shared deterministic test-only pattern.
        let queue = authorizationEntry(AuthorizationKind.Queues, queues, policy)
        assert queue.error == AuthorizationError.None
        let root = stateTrieRoot([encoded.value, queue.value], StateTrieLimits(items: ElementLimit(2),
          perValue: ByteLimit(high(uint64)), totalValueBytes: ByteLimit(high(uint64)),
              nodes: TrieNodeLimit(1000)))
        assert root.error == StateTrieError.None
        echo hex(array[32, byte](root.value.root)) & " " & $root.value.nodes
  of "D":
    # Full input validation precedes immutable owned copies; suffixes remain outside the snapshot.
    var wire = unhex(parts[5])
    let decoded = decodeAuthorization(kind, wire, policy)
    if decoded.error != AuthorizationError.None:
      echo ($decoded.error).toLowerAscii() # No partial rows or consumed cursor on error.
    else:
      for i in 0..<wire.len: wire[i] = 0 # Observe data after destruction of all caller wire bytes.
      let owner = decoded.value.snapshot
      let cores = authorizationCores(owner)
      let observedKind = authorizationKind(owner)
      assert cores.error == AuthorizationError.None and observedKind.error ==
          AuthorizationError.None
      var output = $decoded.value.consumed & " " & $cores.value & " " & $ord(observedKind.value)
      # Owner-bound row counts preserve empty pools rather than flattening away their positions.
      for i in 0..<cores.value:
        let core = AuthorizationCoreIndex(i)
        let count = authorizerCount(owner, core)
        assert count.error == AuthorizationError.None
        var bytes: seq[byte] = @[]
        # Each extraction is a complete independent hash copy with explicit core/row ordinals.
        for j in 0..<count.value:
          let hash = authorizerAt(owner, core, AuthorizationIndex(j))
          assert hash.error == AuthorizationError.None
          # Append each copied identity through the supported single-element sequence API.
          for octet in hash.value.bytes: bytes.add(octet)
        output.add(" " & $count.value & ":" & hex(bytes))
      echo output
  else: assert false # Unknown trusted operations cannot implicitly choose a state schema.

# Keep trusted file/argument parsing outside the typed protocol-error contract.
proc main() {.raises.} =
  # Every request releases mutable source rows and retained handles independently.
  for line in lines(paramStr(1)):
    if line.len > 0: request(line.splitWhitespace()) # Empty batch lines contain no operation.
try:
  main()
except:
  # Trusted transport errors fail independently of ordinary protocol rejection.
  quit(2)
