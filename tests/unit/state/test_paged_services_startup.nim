# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual full Services startup selects a paged directory explicitly and binds only its intact V2 local state/context.
import std/[assertions, syncio, envvars]
import ../../../src/app/[services, options, chain, checkpoint_identity, checkpoint_codec, checkpoint_recovery]
import ../../../src/codec/[bounded, header]
import ../../../src/state/store
import ../../support/application_checkpoint_context
import ../../../src/chain/[genesis, provider]
proc appPid(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Process-private application namespaces preserve earlier forensic artifacts without stale test collisions.
proc configured(path: string, layout: string): Options =
  ## Harness-owned configured genesis is captured before listeners or storage become observable.
  result = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", getEnv(
      "RAGNAROK_APPLICATION_CHECKPOINT"),
    "--state-storage", "disk", "--state-db", path, "--state-layout", layout], result)
proc imported() {.raises.} =
  ## Independently trusted checkpoint import creates exclusively; ordinary local restart preserves its selected header instead of genesis.
  let source = checkpointFixture(CheckpointFixtureVariant.Header)
  let expected = captureApplicationCheckpointIdentity(source).value
  let original = captureApplicationCheckpointIdentity(checkpointFixture()).value
  assert not sameApplicationCheckpoint(expected, original)
  let envelope = encodeApplicationCheckpoint(source, ByteLimit(4194304)).value
  let selectedHeader = source.chainView.bestBlock.value.header
  var wire = newSeq[byte](selectedHeader.headerInfo.value.consumed)
  assert encodeOwnedHeader(selectedHeader, wire).error == HeaderError.None
  let recovered = decodeRecoveryCheckpoint(envelope, wire, expected, genesisStoreLimits(),
      ByteLimit(4194304))
  let path = "paged-services-import-" & $appPid()
  var selected = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", getEnv(
      "RAGNAROK_APPLICATION_CHECKPOINT"),
    "--state-storage", "disk", "--state-layout", "paged", "--state-db", path,
    "--state-writes", "0", "--state-write-bytes", "0"], selected)
  var owner = default(Services)
  defer: owner.close() # Every rejected or successful recovery startup joins every worker and retires its lease.
  let absent = default(ApplicationRecoveryResult)
  assert not owner.startRecovered(selected, "missing independent trust", absent)
  assert owner.startRecovered(selected, "trusted paged import", recovered)
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, expected)
  owner.close()
  assert owner.start(selected, "local paged import restart")
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, expected)
  owner.close()
  assert not owner.startRecovered(selected, "no imported overwrite", recovered)
  owner.close()
  assert owner.start(selected, "preserved imported head")
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, expected)
  owner.close()
proc main() {.raises.} =
  ## Exclusive locking and wrong-layout/corrupt-CURRENT refusals never replace an existing selected epoch.
  let path = "paged-services-startup-" & $appPid()
  var owner = default(Services)
  var competitor = default(Services)
  defer:
    competitor.close()
    owner.close()
  let selected = configured(path, "paged")
  assert owner.start(selected, "validator")
  let before = owner.chainView.bestBlock.value
  assert not competitor.start(selected, "validator")
  competitor.close()
  owner.close()
  assert owner.start(selected, "validator")
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](
      before.blockHash)
  assert array[32, byte](owner.chainView.bestBlock.value.stateRoot) == array[32, byte](
      before.stateRoot)
  assert owner.chainView.retainedCount == 1
  assert owner.chainView.finalizedBlock.error == GenesisError.Unavailable
  owner.close()
  let current = path & "/CURRENT"
  let intact = readFile(current)
  assert not owner.start(configured(path, "journal"), "validator")
  owner.close()
  assert readFile(current) == intact
  assert not owner.start(configured(path, "managed"), "validator")
  owner.close()
  assert readFile(current) == intact
  var corrupt = intact
  corrupt[corrupt.high] = char(ord(corrupt[corrupt.high]) xor 1)
  writeFile(current, corrupt)
  assert not owner.start(selected, "validator")
  owner.close()
  assert readFile(current) == corrupt # Normal startup cannot reset or fall back after integrity refusal.
  writeFile(current, intact)
  assert owner.start(selected, "validator")
  owner.close()
  imported()
  # Exact native directories remain under the ignored runner working path for inspection.
try:
  main()
except:
  quit(2)
echo "PASS paged services startup: V2 full context, local restart, lock and wrong-layout/corrupt-head refusal"
