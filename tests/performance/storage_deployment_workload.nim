# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Larger distinct-payload backend lifetimes verify exact heads before and after strict durable reopen.
import std/[assertions, cmdline, syncio]
import std/posix/posix
import ../support/[storage_deployment_samples, storage_deployment_backends, storage_allocations,
  managed_storage_samples]
import ../../src/storage/[node_repository, file_repository, database_identity, managed_manifest]

type DeploymentObservation = object
  ## Scalar witnesses cannot keep native owners or immutable graphs alive after scope retirement.
  baseline, owner, reopened, closed, released, stored, checks: int
  generation: uint64

proc observeDeployment(engine, path: string, count, steps: int): DeploymentObservation {.raises.} =
  ## Caller-owned CLI strings remain stable throughout every allocator observation in this scope.
  let baseline = occupiedStorageBytes()
  var ownerBytes = 0
  var reopenBytes = -1
  var closedBytes = 0
  var stored = 0
  var generation = 0'u64
  block:
    var memory = default(NodeRepository)
    var disk = default(FileRepository)
    defer:
      if disk.opened:
        discard disk.close # Actual native owners are released even when validation refuses.
    let root = populateDeployment(memory, disk, engine, path, count, steps)
    ownerBytes = occupiedStorageBytes()
    let held = if engine == "memory": memory.snapshot.value else: disk.snapshot.value
    stored = held.storedNodes
    generation = uint64(held.generation)
    checkDeploymentHead(held, root, count, steps)
    if engine != "memory":
      # Strict open has no repair, fallback, migration or checkpoint-authority shortcut.
      assert disk.close == FileError.None, "deployment close failed"
      if engine == "journal":
        assert openFileRepository(disk, path, default(StorageChainId), deploymentJournal()) ==
            FileError.None, "deployment strict journal reopen failed"
      else:
        let reopened = openManagedFileRepository(disk, path, default(StorageChainId),
            deploymentManaged())
        assert reopened == FileError.None, "deployment strict managed reopen failed"
      reopenBytes = occupiedStorageBytes()
      checkDeploymentDisk(disk, root, count, steps)
      assert disk.close == FileError.None, "deployment close failed"
    else:
      assert memory.close == RepositoryError.None
    closedBytes = occupiedStorageBytes()
    checkDeploymentHead(held, root, count, steps)
    if engine == "journal":
      # Cleanup owns only this exclusively created synthetic path after all native leases close.
      var nativePath = path
      assert posix.unlink(nativePath.toCString()) == 0
    elif engine == "managed":
      removeManagedSample(path, [ManagedEpoch(1)])
  let released = occupiedStorageBytes()
  assert ownerBytes > baseline and closedBytes > baseline, "deployment owner/reader absent"
  assert released == baseline, "deployment release baseline=" & $baseline & " released=" & $released
  let checks = count*(if engine == "memory": 2 else: 3)
  result = DeploymentObservation(baseline: baseline, owner: ownerBytes, reopened: reopenBytes,
    closed: closedBytes, released: released, stored: stored, checks: checks, generation: generation)

proc main() {.raises.} =
  ## Fixed axes bound preparation, file extents and complete-map validation on every backend.
  assert paramCount() == 4 and paramStr(1) in ["memory", "journal", "managed"]
  assert paramStr(2) in ["32768", "65536", "131072"] and paramStr(3) in ["16", "64"]
  let engine = paramStr(1)
  let count = if paramStr(2) == "32768": 32768 elif paramStr(2) == "65536": 65536 else: 131072
  let steps = if paramStr(3) == "16": 16 else: 64
  let path = paramStr(4) & "/store"
  let observed = observeDeployment(engine, path, count, steps)
  echo "deployment\t", engine, "\t", count, "\t", steps, "\t", observed.generation,
    "\t", observed.stored, "\t", observed.baseline, "\t", observed.owner, "\t", observed.reopened,
    "\t", observed.closed, "\t", observed.released, "\t", observed.checks

try:
  main()
except:
  quit(2)
