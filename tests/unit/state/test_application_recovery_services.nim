# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_recovery_services_arc_release"}

## Explicit recovered startup installs the exact map/header pair before listener setup and retains no false finality.
import std/[assertions, syncio, envvars]
import ../../../src/app/[services, options, chain, checkpoint_identity, checkpoint_codec, checkpoint_recovery]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, state_layout]
import ../../../src/state/store
import ../../support/[application_checkpoint_context, arc_evidence]
proc recovered(variant: CheckpointFixtureVariant): ApplicationRecoveryResult {.raises.} =
  ## Original producer graph and input bytes retire before Services receives the restored owner.
  let source = checkpointFixture(variant)
  let expected = captureApplicationCheckpointIdentity(source).value
  let envelope = encodeApplicationCheckpoint(source, ByteLimit(high(uint64))).value
  let header = source.chainView.bestBlock.value.header
  var wire = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, wire).error == HeaderError.None
  decodeRecoveryCheckpoint(envelope, wire, expected, genesisStoreLimits(), ByteLimit(high(uint64)))
proc cycle(options: Options, restored: ApplicationRecoveryResult) {.raises.} =
  ## Closed aggregate lifetimes release their canonical/input owners without starting threads or listeners.
  var owner = default(Services)
  defer: owner.close()
  assert owner.startRecovered(options, "recovery", restored)
  assert sameStateSnapshot(owner.stateSnapshot.value, restored.value.stateSnapshot.value)
  assert owner.chainView.retainedCount == 1
  assert owner.chainView.finalizedBlock.error != GenesisError.None
  assert not owner.startRecovered(options, "repeat", restored) # Live aggregates cannot be replaced.
proc main() {.raises.} =
  ## Recovery never falls back to genesis when supplied trust, context or startup options refuse.
  var options = default(Options)
  assert parseOptions(@["server", "--with-state", "--chain", getEnv(
      "RAGNAROK_APPLICATION_CHECKPOINT"), "--state-writes", "0", "--state-write-bytes", "0"], options)
  let restored = recovered(CheckpointFixtureVariant.Header)
  let expected = captureApplicationCheckpointIdentity(restored.value).value
  let original = captureApplicationCheckpointIdentity(checkpointFixture()).value
  assert not sameApplicationCheckpoint(expected, original) # Selected trusted header deliberately differs from configured genesis.
  var owner = default(Services)
  defer: owner.close()
  let absentRecovery = default(ApplicationRecoveryResult)
  assert not owner.startRecovered(options, "absent", absentRecovery)
  assert not owner.startRecovered(default(Options), "invalid", restored)
  assert owner.chainView.retainedCount == 0
  let wrongProfile = recovered(CheckpointFixtureVariant.Profile)
  assert not owner.startRecovered(options, "wrong profile", wrongProfile)
  assert owner.chainView.retainedCount == 0
  assert owner.startRecovered(options, "recovered", restored)
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, expected)
  assert sameStateSnapshot(owner.stateSnapshot.value, restored.value.stateSnapshot.value)
  assert owner.chainView.retainedCount == 1 and owner.chainView.finalizedBlock.error !=
      GenesisError.None
  assert not owner.startRecovered(options, "refused repeat", absentRecovery)
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, expected)
  var branch = forkStateStore(owner.stateSnapshot.value).value
  let refused = branch.apply([StateWrite(key: chapterKey(StateChapter(250)),
      kind: StateWriteKind.Put, value: @[1'u8])])
  assert refused.error == StateStoreError.LimitExceeded # Startup cannot widen a restored read-only policy.
  owner.close()
  assert owner.chainView.retainedCount == 0
  assert owner.startRecovered(options, "restart", restored)
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, expected)
  owner.close()
  cycle(options, restored)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(options, restored) # Stable service lifetimes leave no listener/canonical aliases behind.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_recovery_services", 1000, before, after)
  echo "PASS application recovery services: exact recovered seed, profile preflight, inherited policy and clean restart"
try:
  main() # Fixture/service failures cannot become successful partial startup.
except:
  quit(2)
