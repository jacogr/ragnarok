# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authenticate every detached entry against an independently qualified successor and retain physical/source ownership across input mutation and scope retirement.
import std/[assertions, syncio, envvars, cmdline]
import ../support/[collected_native_context, collected_supplied_context]
import ../../src/app/[logical_checkpoint_import, logical_checkpoint, chain]
import ../../src/state/[current_logical, current_checkpoint, checkpoint, store]
import ../../src/codec/[bounded, state_trie]
import ../../src/chain/genesis
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Exercise genuine backend refusal independently of shape and root validation.
proc escaped(): ImportedLogicalCheckpoint {.raises.} =
  ## Retain only the import while every fixture, capsule and wire alias retires.
  let fixture = collectedNativeFixture()
  let logical = suppliedNativeState(fixture)
  let wire = captureLogicalCheckpoint(logical, ByteLimit(1048576)).value.copyCurrentCheckpoint(
      ByteLimit(1048576)).value
  importLogicalCheckpoint(logical, wire, genesisStoreLimits(), ByteLimit(1048576)).value
proc main() {.raises.} =
  let mode = if paramCount() > 0: paramStr(1) else: "control"
  let empty = default(LogicalCheckpointImportResult[ImportedLogicalCheckpoint])
  if mode == "value":
    discard empty.value
    return
  if mode == "reason":
    discard empty.checkpointError
    return
  if getEnv("RAGNAROK_STATE_REPORT").len == 0:
    putEnv("RAGNAROK_STATE_REPORT", "tests/fixtures/state-report.bin") # Supported unit runs retain their explicit absolute fixture binding.
  let fixture = collectedNativeFixture()
  let logical = suppliedNativeState(fixture)
  let original = logical.currentLogicalContext.value.state
  var wire = captureLogicalCheckpoint(logical, ByteLimit(1048576)).value.copyCurrentCheckpoint(
      ByteLimit(1048576)).value
  let captured = importLogicalCheckpoint(logical, wire, genesisStoreLimits(), ByteLimit(uint64(
      wire.len))).value
  let restored = captured.importedLogicalSnapshot.value
  assert not sameStateSnapshot(original, restored)
  assert sameStateSnapshot(captured.importedLogicalSource.value.currentLogicalContext.value.state, original)
  assert array[32, byte](restored.commitment.root) == array[32, byte](original.commitment.root)
  assert restored.commitment.entries == original.commitment.entries
  for index in 0..<original.commitment.entries:
    let key = original.keyAt(StateEntryIndex(index)).value
    assert restored.lookup(key).value.bytes == original.lookup(
        key).value.bytes # Check every actual raw value, including complete metadata and logical namespaces.
  let wrong = encodeFullCheckpoint(fixture.chain.stateSnapshot.value, ByteLimit(1048576)).value
  assert importLogicalCheckpoint(logical, wrong, genesisStoreLimits(), ByteLimit(
      1048576)).checkpointError == CheckpointError.RootMismatch
  assert importLogicalCheckpoint(logical, wire, genesisStoreLimits(), ByteLimit(uint64(
      wire.len)-1)).checkpointError == CheckpointError.LimitExceeded
  var small = genesisStoreLimits()
  small.trie.items = ElementLimit(uint64(original.commitment.entries)-1)
  assert importLogicalCheckpoint(logical, wire, small, ByteLimit(1048576)).checkpointError ==
      CheckpointError.LimitExceeded
  fail(1)
  assert importLogicalCheckpoint(default(CurrentLogicalState), wire, genesisStoreLimits(),
      ByteLimit(1048576)).error == LogicalCheckpointImportError.InvalidLogical
  assert importLogicalCheckpoint(logical, wire, genesisStoreLimits(), ByteLimit(
      1048576)).checkpointError == CheckpointError.BackendFailure
  fail(0)
  assert importLogicalCheckpoint(logical, wire, genesisStoreLimits(), ByteLimit(1048576)).error ==
      LogicalCheckpointImportError.None
  wire[wire.len-1] = wire[wire.len-1] xor 1'u8
  assert importLogicalCheckpoint(logical, wire, genesisStoreLimits(), ByteLimit(
      1048576)).checkpointError == CheckpointError.RootMismatch
  assert array[32, byte](restored.commitment.root) == array[32, byte](original.commitment.root)
  wire.setLen(0)
  assert restored.commitment.entries == original.commitment.entries
  assert importedLogicalSnapshot(default(ImportedLogicalCheckpoint)).error ==
      LogicalCheckpointImportError.InvalidImport
  assert importedLogicalSource(default(ImportedLogicalCheckpoint)).error ==
      LogicalCheckpointImportError.InvalidImport
  let outside = escaped()
  assert outside.importedLogicalSnapshot.value.commitment.entries > 0
  echo "application-logical-checkpoint-import: ok"
try:
  main()
except:
  quit(2) # Setup and decoding errors cannot impersonate strict result-extraction rejection.
