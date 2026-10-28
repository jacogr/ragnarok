# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real TLS downloads preserve confirmed progress, complete retained maps and explicit finality through migration and per-child compaction.
import std/assertions
import std/syncio
import std/envvars
import std/posix/posix
import ../../support/app_download_chain
import ../../support/app_download_command_context
import ../../support/app_download_disk_context
import ../../support/app_block_download_transport
import ../../support/app_managed_storage_samples
import ../../../src/app/download_command as app_download_command
import ../../../src/app/services as app_services
import ../../../src/app/options as app_options
import ../../../src/chain/genesis as chain_genesis
import ../../../src/chain/provider as chain_provider
import ../../../src/state/store as state_store
import ../../../src/storage/managed_manifest as storage_managed_manifest
import ../../../src/storage/managed_io as storage_managed_io
import ../../../src/storage/file_errors as storage_file_errors
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
const
  ChainPath = "managed-download-chain.json"
  PolicyPath = "managed-download-policy.conf"
proc extra(path: string, migration = ""): seq[string] =
  ## Native command selection is explicit and retains the existing fixed execution/write policy.
  result = @["--state-storage", "disk", "--state-db", path, "--state-layout", "managed",
      "--state-compact-bytes", "1"]
  if migration.len > 0:
    result.add("--state-migrate-from"); result.add(migration)
proc configured(path: string): Options =
  ## Synchronous inspection disables automatic maintenance and does not mutate test-owned forensic staging files.
  result = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", ChainPath, "--state-writes", "1000",
    "--state-write-bytes", "1000000", "--state-storage", "disk", "--state-db", path,
    "--state-layout", "managed", "--state-compact-bytes", "0"], result)
proc checkPrefix(context: DownloadChainFixture, completed: int, path: string,
    finalized = -1) {.raises.} =
  ## Independent complete-map expectations cover every rolling entry and separately retained finality.
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(configured(path), "verify managed download prefix")
  let view = owner.chainView
  assert array[32, byte](view.bestBlock.value.blockHash) == array[32, byte](context.heads[
      completed].blockHash)
  assert sameCompleteState(owner.stateSnapshot.value, context.heads[completed].stateSnapshot)
  assert view.retainedCount == min(completed+1, MaxRetainedBlocks)
  let first = max(0, completed+1-MaxRetainedBlocks)
  for index in first..completed:
    let actual = view.blockAt(context.heads[index].blockHash).value
    assert sameCompleteState(actual.stateSnapshot, context.heads[index].stateSnapshot)
  if finalized >= 0:
    assert array[32, byte](view.finalizedBlock.value.blockHash) == array[32, byte](context.heads[
        finalized].blockHash)
    assert sameCompleteState(view.finalizedBlock.value.stateSnapshot, context.heads[
        finalized].stateSnapshot)
  else:
    assert view.finalizedBlock.error == GenesisError.Unavailable
  owner.close()
proc main() {.raises.} =
  ## Signed real children are authored before any forked responders or Services worker starts.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index, octet in raw: wire[index] = byte(octet)
  let context = chainFixture(decodeOwnedReport(wire, 2).value, 8)
  var legacy = "managed-download-legacy.wal"
  let path = "managed-download-store"
  let failedPath = "managed-download-failure"
  defer:
    for name in [ChainPath, PolicyPath]:
      var temporary = name
      discard posix.unlink(temporary.toCString())
  initializeFinalizedPrefix(context, legacy)
  let original = readFile(legacy)
  let healthy = @[DownloadTransferMode.Healthy, DownloadTransferMode.Healthy]
  let migrated = exchangeDownloads(context, @[responseFrame(context.children[1]), responseFrame(
      context.children[2])],
    healthy, 2, downloadLimits(), ChainPath, PolicyPath, "managed-migrated", extra(path, legacy),
        firstChild = 1)
  assert migrated.outcome.error == DownloadCommandResult.Adopted and
      migrated.outcome.adoptedBlocks == 2
  assert migrated.secondRequests == 2 and readFile(legacy) == original
  checkPrefix(context, 3, path, 0)
  var responses: seq[seq[byte]] = @[]
  var modes: seq[DownloadTransferMode] = @[]
  for index in 3..<8:
    responses.add(responseFrame(context.children[index])); modes.add(DownloadTransferMode.Healthy)
  let resumed = exchangeDownloads(context, responses, modes, 5, downloadLimits(), ChainPath,
      PolicyPath,
    "managed-resumed", extra(path), firstChild = 3)
  assert resumed.outcome.error == DownloadCommandResult.Adopted and resumed.outcome.adoptedBlocks == 5
  assert resumed.secondRequests == 5 and readFile(legacy) == original
  checkPrefix(context, 8, path, 0)
  assert readFile(path & "/journal-0000000000000008.wal").len == ManagedJournalHeaderBytes
  var owner = default(Services)
  assert owner.start(configured(failedPath), "seed failure witness")
  owner.close()
  var directory = default(ManagedDirectory)
  assert openManagedDirectory(directory, failedPath) == FileError.None
  assert createManagedFile(directory, ManagedFileKind.Snapshot, ManagedEpoch(3), [99'u8], ByteLimit(
      1)) == FileError.None
  assert directory.close == FileError.None # A farther unknown epoch survives bounded startup cleanup and is never overwritten.
  let refused = exchangeDownloads(context, @[responseFrame(context.children[0]), responseFrame(
      context.children[1]),
    responseFrame(context.children[2])], @[DownloadTransferMode.Healthy,
    DownloadTransferMode.Healthy,
    DownloadTransferMode.Healthy], 3, downloadLimits(), ChainPath, PolicyPath,
        "managed-maintenance-refusal", extra(failedPath))
  assert refused.outcome.error == DownloadCommandResult.StorageMaintenanceFailure
  assert refused.outcome.adoptedBlocks == 2 and refused.secondRequests == 2
  checkPrefix(context, 2, failedPath)
  assert readFile(failedPath & "/snapshot-0000000000000003.bin") == "c"
  removeManagedSample(failedPath, [ManagedEpoch(1), ManagedEpoch(2), ManagedEpoch(3)])
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2), ManagedEpoch(3), ManagedEpoch(4),
    ManagedEpoch(5), ManagedEpoch(6), ManagedEpoch(7), ManagedEpoch(8)])
  assert posix.unlink(legacy.toCString()) == 0
try:
  main()
except:
  quit(2)
echo "PASS managed download TLS: source-preserving migration, eight-head history/finality, per-child reclaim and confirmed failure prefix"
