# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed startup preserves external checkpoint trust, exclusive import and independent local restart semantics.
import std/[assertions, syncio, envvars]
import ../../support/[application_checkpoint_context, managed_storage_samples]
import ../../../src/app/[services, options, chain, checkpoint_identity, checkpoint_codec, checkpoint_recovery]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/store
import ../../../src/storage/managed_manifest
import ../../../src/codec/[bounded, header, state_layout]
proc recovered(): ApplicationRecoveryResult {.raises.} =
  ## The fixture supplies a separate expected identity and exact sealed bytes; no execution-authentication claim is made.
  let source = checkpointFixture(CheckpointFixtureVariant.Header)
  let expected = captureApplicationCheckpointIdentity(source).value
  let envelope = encodeApplicationCheckpoint(source, ByteLimit(high(uint64))).value
  let header = source.chainView.bestBlock.value.header
  var wire = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, wire).error == HeaderError.None
  decodeRecoveryCheckpoint(envelope, wire, expected, genesisStoreLimits(), ByteLimit(high(uint64)))
proc main() {.raises.} =
  ## An explicit import never resumes or overwrites an existing destination, even when the imported head agrees.
  let restored = recovered()
  assert restored.error == ApplicationRecoveryError.None
  let path = "managed-checkpoint-import"
  let base = @["server", "--with-state", "--chain", getEnv("RAGNAROK_APPLICATION_CHECKPOINT"),
    "--state-writes", "0", "--state-write-bytes", "0", "--state-storage", "disk", "--state-db", path,
    "--state-layout", "managed"]
  var options = default(Options)
  assert parseOptions(base, options)
  var owner = default(Services)
  defer: owner.close()
  assert owner.startRecovered(options, "import", restored)
  let expected = restored.value.chainView.bestBlock.value
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](
      expected.blockHash)
  assert owner.chainView.retainedCount == 1 and owner.chainView.finalizedBlock.error ==
      GenesisError.Unavailable
  owner.close()
  let current = path & "/CURRENT"
  let exact = readFile(current)
  assert not owner.startRecovered(options, "exclusive import", restored)
  owner.close()
  assert readFile(current) == exact
  var imported = base
  for value in ["--state-checkpoint", "missing-checkpoint", "--state-trust", "missing-trust",
    "--state-header", "missing-header", "--state-checkpoint-bytes", "100000"]:
    imported.add(value)
  assert parseOptions(imported, options)
  assert not owner.start(options, "missing external trust")
  owner.close()
  assert readFile(current) == exact # Explicit import intent cannot silently select the already admitted local head.
  assert parseOptions(base, options)
  assert owner.start(options, "local restart")
  assert array[32, byte](owner.chainView.bestBlock.value.blockHash) == array[32, byte](
      expected.blockHash)
  assert owner.chainView.finalizedBlock.error == GenesisError.Unavailable
  let actual = owner.stateSnapshot.value
  for index in 0..<expected.stateSnapshot.commitment.entries:
    let key = expected.stateSnapshot.keyAt(StateEntryIndex(index)).value
    assert actual.lookup(key).value.bytes == expected.stateSnapshot.lookup(key).value.bytes
  owner.close()
  removeManagedSample(path, [ManagedEpoch(1)])
try:
  main()
except:
  quit(2)
echo "PASS managed checkpoint import: independent trust, exclusive destination, no fallback and local restart"
