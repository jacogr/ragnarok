# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Separate bounded fixture producers from fresh light-file reopen consumers and exact ARC/hash witnesses.
import std/[assertions, cmdline, syncio]
import ../../src/storage/[light_file_cache, light_snapshot, light_state_cache, full_state_trie,
  state_proof, database_identity, file_errors, durability]
import ../../src/codec/[bounded, state_layout, state_trie]
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## A clean observer counts only actual reopen proof/checksum attempts, excluding fixture production.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Every consumer must authenticate exactly the same complete evidence set.
const Count = 4096
proc key(index: int): StateKey =
  ## Leading big-endian two-byte ordinals create exactly17-node proof paths for these4096 entries.
  var raw = default(array[31, byte])
  raw[0] = byte(index shr 8)
  raw[1] = byte(index and 255)
  StateKey(raw)
proc policy(size: int): LightSnapshotLimits =
  ## The benchmark fixes all production limits; command arguments cannot widen the workload.
  LightSnapshotLimits(bytes: ByteLimit(16777216), cache: LightCacheLimits(items: ElementLimit(Count),
    writes: ElementLimit(1), valueBytes: ByteLimit(Count*size),
    proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(size))))
proc hex(root: StateRoot): string =
  ## Serialize only the independently calculated expected root passed explicitly to later consumer processes.
  result = ""
  for octet in array[32, byte](root):
    result.add("0123456789abcdef"[int(octet shr 4)])
    result.add("0123456789abcdef"[int(octet and 15)])
proc root(text: string): StateRoot =
  ## Parse exactly64 trusted benchmark argument characters without accepting alternate encodings.
  assert text.len == 64
  var raw = default(array[32, byte])
  for index in 0..<32:
    var value = 0
    for offset in 0..<2:
      let character = text[index*2+offset]
      assert character in {'0'..'9', 'a'..'f'}
      let digit = if character <= '9': ord(character)-ord('0') else: ord(character)-ord('a')+10
      value = value*16+digit
    raw[index] = byte(value)
  StateRoot(raw)
proc produce(path: string, size: int) =
  ## Producer RSS is excluded from every consumer observation; flat-map hashing independently sets root authority.
  var entries = newSeq[StateEntry](Count)
  for index in 0..<Count:
    var value = newSeq[byte](size)
    for offset in 0..<size: value[offset] = byte((index+offset) and 255)
    entries[index] = StateEntry(key: key(index), value: value)
  let bounds = StateTrieLimits(items: ElementLimit(Count), nodes: TrieNodeLimit(100000),
    perValue: ByteLimit(size), totalValueBytes: ByteLimit(Count*size))
  let expected = stateTrieRoot(entries, bounds).value.root
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: bounds)).value
  assert array[32, byte](trie.commitment.root) == array[32, byte](expected)
  var proofs = newSeq[LightStateProof](Count)
  for index in 0..<Count:
    proofs[index] = LightStateProof(key: key(index), proof: trie.prove(key(index), policy(
        size).cache.proof).value)
    assert proofs[index].proof.nodes.len == 17
  let prepared = prepareLightSnapshot(default(StorageChainId), expected, proofs, policy(size)).value
  var file = default(LightFileCache)
  let config = LightFileConfig(root: expected, limits: policy(size))
  assert initializeLightFileCache(file, path, config, prepared).value ==
      StorageDurability.FileAndDirectorySynced
  assert file.close == FileError.None
  echo hex(expected), "\t", prepared.byteLength
type
  Observation = object ## Copied scalar checkpoints outlive all native/cache resources.
    hashes: cint
    opened, closed: int
proc observe(path: string, size: int, expected: StateRoot): Observation =
  ## Whole-child RSS includes reopen and lookup validation; ARC checkpoints describe only simultaneously live owners.
  var file = default(LightFileCache)
  resetHash(0)
  let config = LightFileConfig(root: expected, limits: policy(size))
  assert openLightFileCache(file, path, config) == FileError.None
  let hashes = calls()
  assert hashes == Count*18+1, "reopen hashes: " & $hashes
  let opened = getOccupiedMem()
  var view = file.snapshot.value
  assert view.len == Count and view.valueBytes == uint64(Count*size)
  for index in 0..<Count:
    let found = view.lookup(key(index)).value
    let value = found.bytes
    assert value.len == size and value[0] == byte(index and 255)
    assert value[size-1] == byte((index+size-1) and 255)
  assert file.close == FileError.None
  let closed = getOccupiedMem()
  assert view.lookup(key(Count-1)).value.bytes.len == size
  Observation(hashes: hashes, opened: opened, closed: closed)
proc consume(path: string, size: int, expected: StateRoot) =
  ## Sample final ARC retirement only after all extraction temporaries and result owners leave their scope.
  let baseline = getOccupiedMem()
  let measured = observe(path, size, expected)
  let released = getOccupiedMem()
  assert released == baseline, "ARC release: " & $baseline & " -> " & $released
  echo "reopen\t", size, "\t", measured.hashes, "\t", baseline, "\t", measured.opened, "\t",
      measured.closed, "\t", released
proc main() =
  ## Fixed input identities and one mode keep production, observer and consumer ownership separate.
  assert paramCount() in [3, 4]
  let mode = paramStr(1)
  let extent = paramStr(2)
  assert extent in ["64", "1024"]
  let size = if extent == "64": 64 else: 1024
  let path = paramStr(3)
  if mode == "produce":
    assert paramCount() == 3
    produce(path, size)
  else:
    assert mode == "consume" and paramCount() == 4
    consume(path, size, root(paramStr(4)))
main()
