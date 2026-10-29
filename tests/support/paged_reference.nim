# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent resident TEST oracle for paged-light bytes; production codec/stream helpers are never used here.
import std/assertions
import ../../src/storage/light/state_cache as light_state_cache
import ../../src/storage/database_identity
import ../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../src/crypto/primitives

type PagedReference* = object ## Explicit test-only complete artifacts make byte-for-byte and rehashed-corruption checks independent.
  bytes*, manifest*: seq[byte]
  pages*: int
proc put*(output: var seq[byte], offset: int, number: uint64, width = 8) =
  ## Test literals/fixture lengths prove fixed-width little-endian writes.
  for index in 0..<width: output[offset+index] = byte((number shr (8*index)) and 255)
proc text(output: var seq[byte], value: string) =
  ## Append exact ASCII domains, including the final LF byte.
  for c in value: output.add(byte(c))
proc hash(input: seq[byte]): array[32, byte] =
  ## Only the maintained primitive is shared; no production layout or traversal code supplies oracle bytes.
  let checked = blake2b256(input)
  assert checked.error == CryptoError.None
  array[32, byte](checked.value)
proc tree(output: var seq[byte], body: seq[byte], pages, first, count: int): array[32, byte] =
  ## Recursive complete left/right/parent emission is independent of production's iterative carry stack.
  var input: seq[byte] = @[]
  if count == 1:
    if first < pages: input.text("RAGNAROK-LIGHT-PAGED-LEAF-V1\n")
    else: input.text("RAGNAROK-LIGHT-PAGED-PAD-V1\n")
    let offset = input.len
    input.setLen(offset+8)
    put(input, offset, uint64(first))
    if first < pages:
      for index in 0..<4096: input.add(body[first*4096+index])
  else:
    let left = tree(output, body, pages, first, count div 2)
    let right = tree(output, body, pages, first+count div 2, count div 2)
    input.text("RAGNAROK-LIGHT-PAGED-NODE-V1\n")
    for octet in left: input.add(octet)
    for octet in right: input.add(octet)
  result = hash(input)
  for octet in result: output.add(octet)
proc recommit*(fixture: var PagedReference) =
  ## Rehash arbitrary body mutations so strict proof/shape checks cannot hide behind checksum failure.
  var body = newSeq[byte](fixture.pages*4096)
  for index in 0..<body.len: body[index] = fixture.bytes[index]
  fixture.bytes = body
  var leaves = 1
  while leaves < fixture.pages: leaves *= 2
  let root = tree(fixture.bytes, body, fixture.pages, 0, leaves)
  var selected: seq[byte] = @[]
  if body["RAGNAROK-LIGHT-PAGED-V".len] == byte('2'):
    selected.text("RAGNAROK-LIGHT-PAGED-MANIFEST-V2\n") # Explicit test V2 header selects exactly its matching CURRENT domain.
  else:
    selected.text("RAGNAROK-LIGHT-PAGED-MANIFEST-V1\n") # Existing V1 oracle remains byte-identical.
  for index in 24..<104: selected.add(body[index])
  let fields = selected.len
  selected.setLen(fields+16)
  put(selected, fields, uint64(fixture.pages))
  put(selected, fields+8, uint64(fixture.bytes.len))
  for octet in root: selected.add(octet)
  let checksum = hash(selected)
  for octet in checksum: selected.add(octet)
  assert selected.len == 193
  fixture.manifest = selected
proc pagedReference*(chain: StorageChainId, root: StateRoot,
    records: seq[LightStateProof], context: seq[byte] = @[], epoch = 1'u64,
        sequence = 0'u64): PagedReference =
  ## Assemble exact header/index/payload independently, accepting malformed proof semantics intentionally for tests.
  var payload: seq[byte] = @[]
  var indexBytes = newSeq[byte](64*records.len)
  for ordinal, record in records:
    # Test-size inputs permit simple arithmetic; untrusted production inputs never enter this oracle.
    let start = payload.len
    let key = array[31, byte](record.key)
    for octet in key: payload.add(octet)
    let fields = payload.len
    payload.setLen(fields+10)
    put(payload, fields, uint64(record.proof.nodes.len), 2)
    put(payload, fields+2, uint64(record.proof.value.len))
    for node in record.proof.nodes:
      for octet in array[64, byte](node): payload.add(octet)
    for octet in record.proof.value: payload.add(octet)
    for slot in 0..<31: indexBytes[64*ordinal+slot] = key[slot]
    put(indexBytes, 64*ordinal+31, uint64(start))
    put(indexBytes, 64*ordinal+39, uint64(payload.len-start))
  let indexPages = (indexBytes.len+4095) div 4096
  let payloadPages = (payload.len+4095) div 4096
  let contextPages = (context.len+4095) div 4096
  result = PagedReference(bytes: newSeq[byte]((1+indexPages+payloadPages+contextPages)*4096),
      pages: 1+indexPages+payloadPages+contextPages)
  let magic = if context.len > 0: "RAGNAROK-LIGHT-PAGED-V2\n" else: "RAGNAROK-LIGHT-PAGED-V1\n"
  for slot, c in magic: result.bytes[slot] = byte(c)
  for slot in 0..<32:
    result.bytes[24+slot] = array[32, byte](chain)[slot]
    result.bytes[56+slot] = array[32, byte](root)[slot]
  put(result.bytes, 88, epoch)
  put(result.bytes, 96, sequence)
  put(result.bytes, 104, uint64(records.len))
  put(result.bytes, 112, uint64(payload.len))
  put(result.bytes, 120, uint64(context.len))
  for slot, octet in context: result.bytes[(1+indexPages+payloadPages)*4096+slot] = octet # Independent context placement.
  for slot, octet in indexBytes: result.bytes[4096+slot] = octet
  for slot, octet in payload: result.bytes[(1+indexPages)*4096+slot] = octet
  result.recommit()
