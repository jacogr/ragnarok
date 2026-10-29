# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Trusted independent state-component adapter; every observation is copied before caller
## storage is destroyed.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/[assertions, cmdline, strutils, syncio, parseutils]
import ../../src/codec/state/[safrole as state_safrole, layout as state_layout, trie as state_trie]
import ../../src/codec/[bounded, assurances]

## Decode trusted hex with a separate token for an empty source.
proc unhex(text: string): seq[byte] =
  if text == "-": return @[] # Empty malformed inputs remain expressible.
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  # Copy source octets without host integer reordering.
  for i in 0..<result.len:
    let pair = text[2*i..2*i+1]
    # Trusted fixture hex contains exactly two lowercase digits per byte.
    for c in pair: assert c in {'0'..'9', 'a'..'f'}
    var octet: byte = 0
    assert parseHex(pair, octet) == 2
    result[i] = octet

## Display exact bytes, preserving leading zeroes.
proc hex(bytes: openArray[byte]): string =
  if bytes.len == 0: return "-" # Retain one token for empty observations.
  result = ""
  # Each output byte is independently observable by Python.
  for b in bytes: result.add(toHex(int(b), 2).toLowerAscii())

# Append copied fixture octets through the supported single-element sequence API.
proc append(output: var seq[byte], bytes: openArray[byte]) =
  # Trusted output storage remains local to one observation.
  for octet in bytes: output.add(octet)

## Fixed typed fields are constructed directly from source bytes, not from production decoder output.
proc fixed[N: static[int]](bytes: openArray[byte], offset: int): array[N, byte] =
  result = default(array[N, byte])
  # Trusted request schemas establish exact field widths before this helper runs.
  for i in 0..<N: result[i] = bytes[offset+i]

## Reconstruct authored validator source records with exact field positions.
proc records(bytes: seq[byte]): seq[StateValidator] =
  assert bytes.len mod 336 == 0
  result = newSeq[StateValidator](bytes.len div 336)
  # Field swaps become visible in encoder output against the independent source wire.
  for i in 0..<result.len:
    let p = i*336
    result[i] = StateValidator(bandersnatch: StateBsKey(fixed[32](bytes, p)),
      ed25519: StateEdKey(fixed[32](bytes, p+32)), bls: StateBlsKey(fixed[144](bytes, p+64)),
      metadata: StateValidatorMetadata(fixed[128](bytes, p+208)))

## Build a fixed entropy source without asking the production decoder to define its schema.
proc entropy(bytes: seq[byte]): StateEntropy =
  result = default(StateEntropy)
  assert bytes.len == 128
  # The four words retain their accumulator/history positions.
  for i in 0..<4: result[i] = StateEntropyWord(fixed[32](bytes, i*32))

## Observe independent state-entry keys and raw payloads.
proc emit(entry: StateEntry) =
  echo hex(array[31, byte](entry.key)) & " " & hex(entry.value)

# Parse complete unsigned fixture values without narrowing through signed host integers.
proc unsigned(text: string): uint64 =
  var number: uint64 = 0
  assert text.len > 0 and parseBiggestUInt(text, number) == text.len
  number

## Read trusted policy tokens as distinct core/element/byte limits.
proc config(parts: seq[string], start: int): ValidatorStateConfig =
  ValidatorStateConfig(cores: CoreCount(unsigned(parts[start])),
    validators: ElementLimit(unsigned(parts[start+1])), maxBytes: ByteLimit(
        unsigned(parts[start+2])))

## Execute one trusted request, selecting complete success before any field/progress access.
proc request(parts: seq[string]) {.raises.} =
  case parts[0]
  of "E":
    # Encoding copies the entire entropy tuple into a chapter-6 entry.
    emit(entropyEntry(entropy(unhex(parts[1]))))
  of "T":
    # E4 source values include native uint32 boundaries.
    emit(timeEntry(StateTime(unsigned(parts[1]))))
  of "ED":
    # Destroy original entropy bytes after decoding, before reading the returned fixed history.
    var bytes = unhex(parts[1])
    let parsed = decodeStateEntropy(bytes)
    if parsed.error != StateComponentError.None: echo ($parsed.error).toLowerAscii() # Failure has no progress.
    else:
      for i in 0..<bytes.len: bytes[i] = 0 # Copied entropy must survive caller mutation.
      var output: seq[byte] = @[]
      # Observe each history word separately rather than round-tripping through the encoder.
      for word in parsed.value.value: append(output, array[32, byte](word))
      echo $parsed.value.consumed & " " & hex(output)
  of "TD":
    # Timeslot decoding consumes exactly four bytes and retains no source pointer.
    var bytes = unhex(parts[1])
    let parsed = decodeStateTime(bytes)
    if parsed.error != StateComponentError.None: echo ($parsed.error).toLowerAscii() # No default zero time on failure.
    else:
      for i in 0..<bytes.len: bytes[i] = 0 # Observe the copied numeric value only after destruction.
      echo $parsed.value.consumed & " " & $uint32(parsed.value.value)
  of "V":
    # Source rosters are authored independently and preserved in order by the encoder.
    var source = records(unhex(parts[5]))
    let parsed = validatorEntry(ValidatorChapter(parseInt(parts[1])), source, config(parts, 2))
    if parsed.error != StateComponentError.None: echo ($parsed.error).toLowerAscii() # No partial payload after rejection.
    else:
      for i in 0..<source.len: source[i] = default(StateValidator) # Entry storage cannot alias source fields.
      emit(parsed.value)
  of "VD":
    # Prefix decoding creates a private immutable owner before the caller destroys the wire.
    var bytes = unhex(parts[4])
    let parsed = decodeStateValidators(bytes, config(parts, 1))
    if parsed.error != StateComponentError.None: echo ($parsed.error).toLowerAscii() # No owner or consumed count on failure.
    else:
      for i in 0..<bytes.len: bytes[i] = 0 # Snapshot field observations must remain intact.
      let owner = parsed.value.value
      let count = validatorCount(owner)
      assert count.error == StateComponentError.None
      var output: seq[byte] = @[]
      # Read fixed copies through the retained owner, without access to its private backing sequence.
      for i in 0..<count.value:
        let item = validatorAt(owner, StateValidatorIndex(i))
        assert item.error == StateComponentError.None
        append(output, array[32, byte](item.value.bandersnatch))
        append(output, array[32, byte](item.value.ed25519))
        append(output, array[144, byte](item.value.bls))
        append(output, array[128, byte](item.value.metadata))
      echo $parsed.value.consumed & " " & $count.value & " " & hex(output)
  of "R":
    # Compose exactly the five implemented chapters into the existing serialized-entry trie API.
    var entries = @[entropyEntry(entropy(unhex(parts[1]))), timeEntry(StateTime(unsigned(parts[2])))]
    let source = records(unhex(parts[3]))
    let policy = ValidatorStateConfig(cores: CoreCount(341), validators: ElementLimit(1023),
        maxBytes: ByteLimit(1_000_000))
    # Same roster contents in distinct chapters must remain distinct trie identities.
    for chapter in [ValidatorChapter.Staging, ValidatorChapter.Active, ValidatorChapter.Previous]:
      let encoded = validatorEntry(chapter, source, policy)
      assert encoded.error == StateComponentError.None
      entries.add(encoded.value)
    let root = stateTrieRoot(entries, StateTrieLimits(items: ElementLimit(5), perValue: ByteLimit(
        1_000_000),
      totalValueBytes: ByteLimit(4_000_000), nodes: TrieNodeLimit(2_000)))
    assert root.error == StateTrieError.None
    echo hex(array[32, byte](root.value.root)) & " " & $root.value.nodes
  else: assert false # Unknown operations must not accidentally select a protocol schema.

# Keep trusted file/argument parsing separate from typed component failures.
proc main() {.raises.} =
  # Each request owns and releases its mutable sources independently.
  for line in lines(paramStr(1)):
    if line.len > 0: request(line.splitWhitespace()) # Empty batch lines have no operation.
try:
  main()
except:
  # Trusted transport errors must not count as ordinary protocol rejection.
  quit(2)
