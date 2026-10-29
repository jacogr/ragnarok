# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Separate native processes prepare and strictly reopen owned larger fixtures with an exact expected root.
import std/[assertions, cmdline, syncio]
import ../support/[storage_deployment_samples, storage_deployment_backends, storage_allocations]
import ../../src/storage/node/repository as node_repository
import ../../src/storage/file/repository as file_repository
import ../../src/storage/database_identity
import ../../src/codec/state/trie as state_trie

proc rootHex(root: StateRoot): string =
  ## The producer emits one canonical lowercase identity without deriving checkpoint or protocol authority.
  const digits = "0123456789abcdef"
  result = ""
  for octet in array[32, byte](root):
    result.add(digits[int(octet shr 4)])
    result.add(digits[int(octet and 15)])

proc expectedRoot(text: string): StateRoot =
  ## The consumer admits exactly32 bytes from the independently completed producer, with no fallback form.
  assert text.len == 64
  var raw = default(array[32, byte])
  for index in 0..<64:
    let c = text[index]
    assert c in {'0'..'9', 'a'..'f'}
    let nibble = if c <= '9': int(c)-int('0') else: int(c)-int('a')+10
    if (index and 1) == 0:
      raw[index div 2] = byte(nibble shl 4)
    else:
      raw[index div 2] = raw[index div 2] or byte(nibble)
  result = StateRoot(raw)

proc prepare(engine, path: string, count: int) {.raises.} =
  ## Producer validation completes and closes the exclusive owner before the consumer process starts.
  var memory = default(NodeRepository)
  var disk = default(FileRepository)
  defer:
    if disk.opened: discard disk.close
  let root = populateDeployment(memory, disk, engine, path, count, 16)
  checkDeploymentDisk(disk, root, count, 16)
  assert disk.close == FileError.None
  echo "prepared\t", engine, "\t", count, "\t16\t17\t", rootHex(root)

proc reopen(engine, path, token: string, count: int) {.raises.} =
  ## Stable borrowed arguments and no prepared fixture graph enter the consumer's measured allocator scope.
  let root = expectedRoot(token)
  let baseline = occupiedStorageBytes()
  var openedBytes = 0
  var closedBytes = 0
  var stored = 0
  block:
    var disk = default(FileRepository)
    defer:
      if disk.opened: discard disk.close
    if engine == "journal":
      assert openFileRepository(disk, path, default(StorageChainId), deploymentJournal()) == FileError.None
    else:
      assert openManagedFileRepository(disk, path, default(StorageChainId), deploymentManaged()) == FileError.None
    openedBytes = occupiedStorageBytes()
    let held = disk.snapshot.value
    stored = held.storedNodes
    checkDeploymentHead(held, root, count, 16)
    assert disk.close == FileError.None
    closedBytes = occupiedStorageBytes()
    checkDeploymentHead(held, root, count, 16)
  let released = occupiedStorageBytes()
  assert openedBytes > baseline and closedBytes > baseline and released == baseline
  echo "reopened\t", engine, "\t", count, "\t16\t17\t", token, "\t", stored,
    "\t", baseline, "\t", openedBytes, "\t", closedBytes, "\t", released, "\t", count*2

proc main() {.raises.} =
  ## Only an absent producer target or an explicitly supplied exact consumer token selects an operation.
  assert paramCount() in [4, 5] and paramStr(1) in ["prepare", "open"]
  assert paramStr(2) in ["journal", "managed"] and paramStr(3) in ["32768", "131072"]
  let mode = paramStr(1)
  let engine = paramStr(2)
  let count = if paramStr(3) == "32768": 32768 else: 131072
  let path = paramStr(4) & "/store"
  if mode == "prepare":
    assert paramCount() == 4
    prepare(engine, path, count)
  else:
    assert paramCount() == 5
    reopen(engine, path, paramStr(5), count)

try:
  main()
except:
  quit(2)
