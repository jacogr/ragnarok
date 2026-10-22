# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen independent namespace identities, supervisor records and full-map roots exercise typed proof reads.
import std/[assertions, envvars, parseutils, strutils, syncio]
import ../../support/proof_service_helpers
import ../../../src/state/[proof_service, proof_view, trie_proof]
import ../../../src/codec/[bounded, state_accounts, state_layout, state_trie, state_service_values, state_requests]
proc unhex(text: string): seq[byte] =
  ## Parse exact fixture bytes without invoking any production state codec.
  if text == "-": return @[]
  assert text.len mod 2 == 0
  result = newSeq[byte](text.len div 2)
  for i in 0..<result.len:
    var value = 0'u8
    assert parseHex(text[2*i..2*i+1], value) == 2
    result[i] = value
proc key(text: string): StateKey =
  ## Every fixture identity contains exactly all 248 committed key bits.
  let bytes = unhex(text)
  assert bytes.len == 31
  var raw = default(array[31, byte])
  for i in 0..<31: raw[i] = bytes[i]
  StateKey(raw)
proc check(line: string) =
  ## Use literal independent complete maps and roots, then compare typed selector and content results.
  let fields = line.splitWhitespace()
  assert fields.len == 12
  var number = 0'u64
  assert parseBiggestUInt(fields[0], number) == fields[0].len
  assert number <= uint64(high(uint32))
  let service = ServiceIndex(uint32(number))
  let raw = unhex(fields[1])
  let storage = unhex(fields[2])
  let blob = unhex(fields[3])
  let digest = unhex(fields[4])
  var hashBytes = default(array[32, byte])
  for i in 0..<32: hashBytes[i] = digest[i]
  let hash = ServicePreimageHash(hashBytes)
  let keys = [key(fields[5]), key(fields[6]), key(fields[7]), key(fields[8])]
  let entries = @[StateEntry(key: keys[0], value: unhex(fields[9])), StateEntry(key: keys[1],
      value: storage), StateEntry(key: keys[2], value: blob), StateEntry(key: keys[3], value: unhex(
      fields[10]))]
  let view = serviceView(entries, keys)
  let expectedRoot = unhex(fields[11])
  let root = array[32, byte](view.root)
  for i in 0..<32: assert root[i] == expectedRoot[i]
  assert uint64(view.readProofAccount(service).value.balance) == 99
  assert uint32(view.readProofAccount(service).value.supervisor) == 17
  assert view.readProofStorage(service, raw, ServiceEntryLimits(keyBytes: ByteLimit(32),
      valueBytes: ByteLimit(33))).value.bytes == storage
  assert view.readProofPreimage(service, hash, ByteLimit(33)).value.bytes == blob
  assert view.readProofHistoricalPreimage(service, hash, RequestSlot(4), ByteLimit(
      33)).value.bytes == blob
  assert view.readProofCode(service, RequestSlot(4), ByteLimit(33)).value.bytes == blob
  let a = planProofStorage(service, raw, ByteLimit(32), ElementLimit(2)).value
  let b = planProofHistorical(service, hash, RequestLength(uint32(blob.len)), ElementLimit(3)).value
  let plan = mergeProofPlans(a, b, ElementLimit(4)).value
  assert view.matchesProofPlan(plan).value
proc main() {.raises.} =
  ## Missing corpus input or skipped rows cannot silently pass an empty verification run.
  let lines = readFile(getEnv("RAGNAROK_STATE_SERVICE_REFERENCE")).splitLines()
  assert lines.len == 5 and lines[4] == ""
  for i in 0..<4: check(lines[i])
  echo "state-proof-service-reference: ok"
try:
  main()
except:
  quit(2) # A malformed independent fixture is a failed test, never a skipped reference gate.
