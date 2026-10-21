# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Every physical decoder rejects reserved addresses and empty branch forms during borrowed preflight.
import std/[assertions, syncio]
import ../../support/storage_samples
import ../../../src/storage/[full_state_trie, node_repository, node_records, record_codec]
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset real primitive attempt observation.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count whether a known malformed shape reaches integrity work.
proc reason(input: openArray[byte], mode: int, limits: RecordLimits): RecordError =
  ## Exercise target transport, generic collection and strict ordered collection through their public APIs.
  if mode == 0: decodeTrieExport(input, limits).error
  elif mode == 1: decodeRecordCollection(input, limits).error
  else: decodeOrderedRecordCollection(input, limits).error
let limits = storageLimits()
var owner = newNodeRepository(limits)
let full = exportFullTrie(storageTrie(), limits.codec.records).value
let view = owner.publish(owner.snapshot.value, full).value
let selected = selectRepositoryRoots(view, [view.commitment.root], typeof(limits.records)(1)).value
let records = exportRepositorySelection(selected, limits.codec.records).value
var sorted = full
sorted.records = records
let target = encodeTrieExport(sorted, limits.codec).value
let collection = encodeRecordCollection(RecordCollection(records: records), limits.codec).value
for mode in 0..2:
  # Identical locally valid nodes cover every supported physical transport domain.
  let original = if mode == 0: target else: collection
  let header = if mode == 0: TrieExportHeaderBytes else: "RAGNAROK-RECORDS-V1".len+1+8
  reset(0)
  assert reason(original, mode, limits.codec) == RecordError.None
  assert int(calls()) == 3
  var address = original
  for index in 0..<32:
    address[header+1+index] = 0 # Zero digest is reserved for an absent subtree, never a stored record.
  reset(0)
  assert reason(address, mode, limits.codec) == RecordError.NonCanonical
  assert int(calls()) == 0
  var branch = original
  var offset = header
  for record in records:
    if record.kind == TrieRecordKind.Branch:
      # Both child identities are zeroed without disturbing tag, extent or canonical address order.
      for index in 0..<64:
        branch[offset+33+index] = 0
      break
    else:
      offset += 72+record.payload.len # Exact fixture descriptors precede the known branch record.
  reset(0)
  assert reason(branch, mode, limits.codec) == RecordError.NonCanonical
  assert int(calls()) == 0
  var corrupt = original
  corrupt[original.len-1] = corrupt[original.len-1] xor 1
  assert reason(corrupt, mode, limits.codec) == RecordError.HashMismatch
assert owner.close == RepositoryError.None
echo "PASS storage record preflight: all decoders, reserved addresses, empty branches and real integrity controls"
