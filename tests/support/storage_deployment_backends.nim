# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Synthetic larger workloads use the same public backend admission and synchronization contracts.
import std/assertions
import ./storage_deployment_samples
import ../../src/storage/[node_repository, file_repository, managed_repository, database_identity]
import ../../src/codec/[bounded, state_layout, state_trie]

proc deploymentJournal*(): JournalLimits =
  ## Selected file and aggregate record budgets remain independently bounded in benchmark-only policy.
  result = JournalLimits(repository: deploymentLimits(), bytes: ByteLimit(134217728))

proc deploymentManaged*(): ManagedLimits =
  ## Explicit managed limits neither choose protocol history nor widen production defaults.
  result = ManagedLimits(repository: deploymentLimits(), roots: ElementLimit(9),
    snapshotBytes: ByteLimit(134217728), journalBytes: ByteLimit(134217728),
        contextBytes: ByteLimit(64))

proc populateDeployment*(memory: var NodeRepository, disk: var FileRepository,
    engine, path: string, count, publications: int): StateRoot {.raises.} =
  ## Prepared graphs and seed-selection aliases retire before the caller observes backend ownership.
  let fixture = prepareDeployment(count, publications)
  if engine == "memory":
    # Memory and durable backends receive identical authored physical changes.
    memory = newNodeRepository(deploymentLimits())
    discard memory.publish(memory.snapshot.value, fixture.seed).value
  elif engine == "journal":
    # Legacy initialization and each publication retain actual journal synchronization.
    assert initializeFileRepository(disk, path, default(StorageChainId), deploymentJournal()) == FileError.None
    let seeded = disk.publish(disk.snapshot.value, fixture.seed)
    assert seeded.error == FileError.None, "deployment seed error=" & $seeded.error
    discard seeded.value
  else:
    # Managed creation publishes one complete selected seed; the temporary memory source retires here.
    assert engine == "managed"
    var seed = newNodeRepository(deploymentLimits())
    let view = seed.publish(seed.snapshot.value, fixture.seed).value
    let selected = selectRepositoryRoots(view, [view.commitment.root], ElementLimit(1)).value
    assert initializeManagedFileRepository(disk, path, default(StorageChainId), selected, [],
      deploymentManaged()) == FileError.None
    assert seed.close == RepositoryError.None
  for change in fixture.changes:
    # Every backend executes the same bounded public publication sequence.
    if engine == "memory":
      discard memory.publish(memory.snapshot.value, change).value
    else:
      let published = disk.publish(disk.snapshot.value, change)
      assert published.error == FileError.None, "deployment update error=" & $published.error
      discard published.value
  result = fixture.roots[publications]

proc checkDeploymentDisk*(disk: var FileRepository, root: StateRoot, count, publications: int) =
  ## Validation views retire before the caller samples subsequent owner-close boundaries.
  checkDeploymentHead(disk.snapshot.value, root, count, publications)
