# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent trusted checkpoint startup supports successive genuine children while preserving exclusive disk imports and trust-free local restart.
import std/[assertions, syncio, envvars, os]
import std/posix/posix
import ../../../src/app/download/command as download_command
import ../../../src/app/checkpoint/[identity as checkpoint_identity, codec as checkpoint_codec]
import ../../../src/app/chain
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, report_owned]
import ../../../src/lib/atomic/file as atomic_file
import ../../support/[application_download_chain, application_candidate_context,
  application_download_command_context, application_download_disk_context, block_download_transport]

const
  ChainPath = "download-import-chain.json"
  PolicyPath = "download-import-policy.conf"
  MapPath = "download-import-map"
  IdentityPath = "download-import-identity"
  HeaderPath = "download-import-header"
  DiskPath = "download-import.db"

proc persist(path: string, bytes: seq[byte]) =
  ## Independent exact regular inputs are fully written before command capture or process startup.
  assert replaceAtomicFile(path, bytes, ByteLimit(uint64(bytes.len))) == AtomicFileError.None

proc controls(extent: int, disk = false): seq[string] =
  ## All four external trust controls remain atomic and distinct from the selected database path.
  result = @["--state-checkpoint", MapPath, "--state-trust", IdentityPath, "--state-header",
    HeaderPath,
    "--state-checkpoint-bytes", $extent]
  if disk:
    for value in ["--state-storage", "disk", "--state-db", DiskPath]: result.add(value)

proc main() {.raises.} =
  ## Capture operator authority from a separately retained original head, before any untrusted checkpoint-file read.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var report = newSeq[byte](raw.len)
  for index, octet in raw: report[index] = byte(octet)
  let context = chainFixture(decodeOwnedReport(report, 2).value, 4)
  let original = initialized(context.seed)
  let identity = captureApplicationCheckpointIdentity(original).value
  let metadata = encodeApplicationCheckpointIdentity(identity, ByteLimit(238)).value
  let envelope = encodeApplicationCheckpoint(original, ByteLimit(1000000)).value
  let header = original.chainView.bestBlock.value.header
  var sealed = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, sealed).error == HeaderError.None
  defer:
    for name in [ChainPath, PolicyPath, MapPath, IdentityPath, HeaderPath, DiskPath]:
      var path = name
      discard posix.unlink(path.toCString()) # Every command/inspection closes its own workers and disk lock first.
  persist(MapPath, envelope)
  persist(IdentityPath, metadata)
  persist(HeaderPath, sealed)
  let first = responseFrame(context.children[0])
  for mode in 0..2:
    var damaged = if mode == 0: metadata elif mode == 1: sealed else: envelope
    damaged[damaged.high] = damaged[damaged.high] xor 1
    persist(if mode == 0: IdentityPath elif mode == 1: HeaderPath else: MapPath, damaged)
    let refused = exchangeDownloads(context, @[first], @[DownloadTransferMode.Healthy], 3,
      downloadLimits(), ChainPath, PolicyPath, "import-refused", controls(envelope.len, true))
    assert refused.outcome.error == DownloadCommandResult.StartupFailure and
        refused.outcome.adoptedBlocks == 0
    assert refused.secondRequests == 0 and not fileExists(
        DiskPath) # No invalid independent identity/header/envelope reaches transport or creates a DB.
    persist(IdentityPath, metadata)
    persist(HeaderPath, sealed)
    persist(MapPath, envelope)
  let responses = @[first, responseFrame(context.children[1]), responseFrame(context.children[2])]
  let healthy = @[DownloadTransferMode.Healthy, DownloadTransferMode.Healthy,
      DownloadTransferMode.Healthy]
  let memory = exchangeDownloads(context, responses, healthy, 3, downloadLimits(), ChainPath,
    PolicyPath, "import-memory", controls(envelope.len))
  assert memory.outcome.error == DownloadCommandResult.Adopted and memory.outcome.adoptedBlocks == 3
  assert memory.secondRequests == 3
  let durable = exchangeDownloads(context, responses, healthy, 3, downloadLimits(), ChainPath,
    PolicyPath, "import-durable", controls(envelope.len, true))
  assert durable.outcome.error == DownloadCommandResult.Adopted and durable.outcome.adoptedBlocks == 3
  assert durable.secondRequests == 3
  for name in [MapPath, IdentityPath, HeaderPath]:
    var path = name
    assert posix.unlink(path.toCString()) == 0 # Normal local restart must not reread even the independently selected trust files.
  assertDiskPrefix(context, 3, ChainPath, DiskPath)
  let resumed = exchangeDownloads(context, @[responseFrame(context.children[3])],
    @[DownloadTransferMode.Healthy], 1, downloadLimits(), ChainPath, PolicyPath, "import-resumed",
    @["--state-storage", "disk", "--state-db", DiskPath], firstChild = 3)
  assert resumed.outcome.error == DownloadCommandResult.Adopted and resumed.outcome.adoptedBlocks == 1
  assertDiskPrefix(context, 4, ChainPath, DiskPath)
  persist(MapPath, envelope)
  persist(IdentityPath, metadata)
  persist(HeaderPath, sealed)
  let before = readFile(DiskPath)
  let overwrite = exchangeDownloads(context, @[first], @[DownloadTransferMode.Healthy], 3,
    downloadLimits(), ChainPath, PolicyPath, "import-existing", controls(envelope.len, true))
  assert overwrite.outcome.error == DownloadCommandResult.StartupFailure and
      overwrite.outcome.adoptedBlocks == 0
  assert overwrite.secondRequests == 0 and readFile(DiskPath) == before
  assertDiskPrefix(context, 4, ChainPath, DiskPath)
  echo "PASS application download import progress: independent trust, genuine successive execution and exclusive durable imports"
try:
  main() # File/native/process errors never count as successful recovery or progress.
except:
  quit(2)
