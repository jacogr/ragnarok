# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit source-preserving migration copies a locked legacy revision into a new managed directory.
## This operation grants no checkpoint import trust and never overwrites or renames the source database.
import ./repository as file_repository
import ../managed/repository as managed_repository
import ../node/repository as node_repository
import ../database_identity
import ../../codec/state/trie as state_trie
type
  MigrationSeed = object ## One exact legacy revision retains its validated root selection and detached context.
    selection: RepositorySelection
    context: seq[byte]
    schema: StorageSchema
  MigrationCapture = object ## Failed capture grants no seed or root authority even inside this module.
    case status: FileError
    of None: seed: MigrationSeed
    else: discard

proc captureMigration(source: FileRepository, chain: StorageChainId,
    roots: openArray[StateRoot], limits: ManagedLimits): MigrationCapture =
  ## Require a live legacy source, then bind chain/schema/current revision and the explicit complete root union.
  let layout = source.managedUsage
  if layout.error == FileError.None: return MigrationCapture(status: FileError.UnsupportedLayout)
  if layout.error != FileError.UnsupportedLayout: return MigrationCapture(status: layout.error)
  let identity = source.chainIdentity
  if identity.error != FileError.None: return MigrationCapture(status: identity.error)
  if array[32, byte](identity.value) != array[32, byte](chain): return MigrationCapture(
      status: FileError.WrongIdentity)
  let schema = source.storageSchema
  if schema.error != FileError.None: return MigrationCapture(status: schema.error)
  let view = source.snapshot
  if view.error != FileError.None: return MigrationCapture(status: view.error)
  let context = source.snapshotContext
  if context.error != FileError.None: return MigrationCapture(status: context.error)
  let selection = selectRepositoryRoots(view.value, roots, limits.roots)
  if selection.error != RepositoryError.None: return MigrationCapture(
      status: FileError.InvalidRetention)
  MigrationCapture(status: FileError.None, seed: MigrationSeed(selection: selection.value,
    context: context.value, schema: schema.value))

proc migrateFileRepository*(source: FileRepository, destination: var ManagedRepository,
    path: string, chain: StorageChainId, roots: openArray[StateRoot],
        limits: ManagedLimits): FileError =
  ## Preserve the original raw managed destination API; no source byte or lock changes during copy.
  if destination.opened: return FileError.Busy
  let captured = captureMigration(source, chain, roots, limits)
  if captured.status != FileError.None: return captured.status
  let seed = captured.seed
  initializeManagedRepository(destination, path, chain, seed.selection, seed.context, limits, seed.schema)

proc migrateFileRepository*(source: FileRepository, destination: var FileRepository,
    path: string, chain: StorageChainId, roots: openArray[StateRoot],
        limits: ManagedLimits): FileError =
  ## A facade destination adopts independent managed ownership only after the same complete source capture.
  if destination.opened: return FileError.Busy
  let captured = captureMigration(source, chain, roots, limits)
  if captured.status != FileError.None: return captured.status
  let seed = captured.seed
  initializeManagedFileRepository(destination, path, chain, seed.selection, seed.context, limits, seed.schema)
