# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit source-preserving migration copies a locked legacy revision into a new managed directory.
## This operation grants no checkpoint import trust and never overwrites or renames the source database.
import ./[file_repository, managed_repository, node_repository, database_identity]
import ../codec/state_trie
proc migrateFileRepository*(source: FileRepository, destination: var ManagedRepository,
    path: string, chain: StorageChainId, roots: openArray[StateRoot],
        limits: ManagedLimits): FileError =
  ## Keep the source lease held while checking its identity, exact selected revision and retained root union.
  if destination.opened: return FileError.Busy
  let identity = source.chainIdentity
  if identity.error != FileError.None: return identity.error
  if array[32, byte](identity.value) != array[32, byte](chain): return FileError.WrongIdentity
  let schema = source.storageSchema
  if schema.error != FileError.None: return schema.error
  let view = source.snapshot
  if view.error != FileError.None: return view.error
  let context = source.snapshotContext
  if context.error != FileError.None: return context.error
  let selection = selectRepositoryRoots(view.value, roots, limits.roots)
  if selection.error != RepositoryError.None: return FileError.InvalidRetention
  initializeManagedRepository(destination, path, chain, selection.value, context.value, limits, schema.value)
