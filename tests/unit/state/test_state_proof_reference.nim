# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen independent Python/hashlib commitments and raw paths cross-check production verification and generation.
import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../../src/state/trie_proof
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
proc unhex(text: string): seq[byte] =
  ## Fixture byte tokens are exact lowercase hexadecimal; a dash is present-empty storage.
  if text == "-": return @[]
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    # Reject malformed fixture input independently of the production proof verdict.
    var value = 0'u8
    assert parseHex(text[2*i..2*i+1], value) == 2
    result[i] = value
proc key(text: string): StateKey =
  ## Preserve all 248 key bits exactly.
  let bytes = unhex(text)
  assert bytes.len == 31
  var raw = default(array[31, byte])
  for i in 0..<31: raw[i] = bytes[i]
  StateKey(raw)
proc check(line: string) {.raises.} =
  ## Compare literal oracle roots/paths with both separately called production directions.
  let fields = line.splitWhitespace()
  let rootBytes = unhex(fields[0])
  assert rootBytes.len == 32
  var root = default(array[32, byte])
  for i in 0..<32: root[i] = rootBytes[i]
  let query = key(fields[1])
  let present = fields[2] == "1"
  let supplied = unhex(fields[3])
  let count = parseInt(fields[4])
  assert count >= 0 and count <= 249
  var nodes = newSeq[EncodedStateNode](count)
  for i in 0..<count:
    # Parse complete fixed nodes without consulting production node encoding helpers.
    let bytes = unhex(fields[5+i])
    assert bytes.len == 64
    var node = default(array[64, byte])
    for j in 0..<64: node[j] = bytes[j]
    nodes[i] = EncodedStateNode(node)
  let entriesCount = parseInt(fields[5+count])
  assert fields.len == 6+count+2*entriesCount
  var entries = newSeq[StateEntry](entriesCount)
  for i in 0..<entriesCount:
    entries[i] = StateEntry(key: key(fields[6+count+2*i]), value: unhex(fields[7+count+2*i]))
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(100))
  let maps = StateTrieLimits(items: ElementLimit(8), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(800), nodes: TrieNodeLimit(3000))
  let witness = captureStateProof(nodes, supplied, limits).value
  let verified = verifyStateProof(witness, StateRoot(root), query, limits).value
  assert verified.present == present
  if present: assert verified.bytes == supplied # Presence, including empty, is separately authenticated.
  let generated = generateStateProof(entries, query, maps, limits).value
  assert generated.len == count and generated.suppliedValue.value == supplied
  for i in 0..<count:
    assert array[64, byte](generated.nodeAt(i).value) == array[64, byte](nodes[i]) # Exact canonical path parity.
proc main() {.raises.} =
  ## Missing fixture input must fail instead of silently passing a zero-case corpus.
  let lines = readFile(getEnv("RAGNAROK_STATE_PROOF")).splitLines()
  assert lines.len == 46 and lines[45] == ""
  for i in 0..<45: check(lines[i])
  echo "state-proof-reference: ok"
try:
  main()
except:
  quit(2) # Fixture/parser errors are test failures, never typed proof refusals.
