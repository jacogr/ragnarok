# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_recovery_startup_arc_release"}

## Parsed external recovery opens independent inputs once, preserves explicit policies and never falls back on refusal.
import std/[assertions, syncio, envvars]
import std/posix/posix
import ../../../src/app/[services, options, chain, checkpoint_identity, checkpoint_codec, checkpoint_file]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/[bounded, header, state_layout]
import ../../../src/state/store
import ../../../src/lib/atomic_file
import ../../support/[application_checkpoint_context, arc_evidence]
const CheckpointPath = "application-recovery-startup-map"
const TrustPath = "application-recovery-startup-identity"
const HeaderPath = "application-recovery-startup-header"
proc selectedOptions(limit = "100000"): Options =
  ## File and mutation policies remain separate explicit controls; no listeners are implied.
  result = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", getEnv(
      "RAGNAROK_APPLICATION_CHECKPOINT"),
    "--state-writes", "0", "--state-write-bytes", "0", "--state-checkpoint", CheckpointPath,
    "--state-trust", TrustPath, "--state-header", HeaderPath, "--state-checkpoint-bytes", limit], result)
proc publishInputs(variant = CheckpointFixtureVariant.Header): ApplicationCheckpointIdentity {.raises.} =
  ## Trusted operator material and the checkpoint remain separate selected files throughout startup.
  let source = checkpointFixture(variant)
  result = captureApplicationCheckpointIdentity(source).value
  let metadata = encodeApplicationCheckpointIdentity(result, ByteLimit(238)).value
  let header = source.chainView.bestBlock.value.header
  var wire = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, wire).error == HeaderError.None
  assert replaceAtomicFile(TrustPath, metadata, ByteLimit(238)) == AtomicFileError.None
  assert replaceAtomicFile(HeaderPath, wire, ByteLimit(300000)) == AtomicFileError.None
  assert saveApplicationCheckpoint(CheckpointPath, source, ByteLimit(100000)).error ==
      ApplicationCheckpointFileError.None
proc cycle(options: Options, expected: ApplicationCheckpointIdentity) {.raises.} =
  ## Every configured startup owns fresh restored graphs and retires all service aliases on close.
  var owner = default(Services)
  defer: owner.close()
  assert not owner.startupBlockAnchor.available
  assert owner.start(options, "checkpoint import")
  let anchor = owner.startupBlockAnchor
  assert anchor.available
  assert array[32, byte](anchor.blockHash) == array[32, byte](
      owner.chainView.bestBlock.value.blockHash)
  assert uint32(anchor.slot) == owner.chainView.bestBlock.value.slot
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, expected)
  assert owner.chainView.retainedCount == 1 and owner.chainView.finalizedBlock.error !=
      GenesisError.None
  owner.close()
  assert not owner.startupBlockAnchor.available # Closed owners retain no live startup authority.
proc main() {.raises.} =
  ## Invalid trust, profile, byte/map limits and native files never activate configured genesis instead.
  defer:
    for selected in [CheckpointPath, TrustPath, HeaderPath]:
      var path = selected
      discard posix.unlink(path.toCString()) # Every test-owned input retires even after an assertion.
  let options = selectedOptions()
  let expected = publishInputs()
  let originalBytes = readBoundedFile(CheckpointPath, ByteLimit(100000)).value
  var owner = default(Services)
  defer: owner.close()
  assert not owner.start(selectedOptions("0"), "tight byte policy")
  assert owner.chainView.retainedCount == 0
  assert not owner.start(options, "tight map policy", default(StateStoreLimits))
  assert owner.chainView.retainedCount == 0
  discard publishInputs(CheckpointFixtureVariant.Profile)
  assert not owner.start(options, "profile mismatch")
  assert owner.chainView.retainedCount == 0
  discard publishInputs()
  assert owner.start(options, "recovered")
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value, expected)
  var branch = forkStateStore(owner.stateSnapshot.value).value
  assert branch.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
      value: @[1'u8])]).error == StateStoreError.LimitExceeded
  var trustPath = TrustPath
  assert posix.unlink(trustPath.toCString()) == 0
  assert not owner.start(options, "live repeat")
  assert sameApplicationCheckpoint(owner.checkpointIdentity.value,
      expected) # Repeated startup touches no trust file and preserves the installed owner.
  owner.close()
  assert not owner.start(options, "missing trust")
  assert owner.chainView.retainedCount == 0
  discard publishInputs()
  var writable = genesisStoreLimits()
  writable.writes = ElementLimit(1)
  writable.writeValueBytes = ByteLimit(1)
  assert owner.start(options, "explicit component policy", writable)
  var inherited = forkStateStore(owner.stateSnapshot.value).value
  assert inherited.apply([StateWrite(key: chapterKey(StateChapter(250)), kind: StateWriteKind.Put,
      value: @[1'u8])]).error == StateStoreError.None
  owner.close()
  cycle(options, expected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(options, expected) # Parsed input paths do not retain any restored map between attempts.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_recovery_startup", 1000, before, after)
  assert readBoundedFile(CheckpointPath, ByteLimit(100000)).value == originalBytes
  var corrupt = originalBytes
  corrupt[0] = corrupt[0] xor 1
  assert replaceAtomicFile(CheckpointPath, corrupt, ByteLimit(100000)) == AtomicFileError.None
  assert not owner.start(options, "corruption")
  assert owner.chainView.retainedCount == 0
  assert readBoundedFile(CheckpointPath, ByteLimit(100000)).value ==
      corrupt # Refusal never repairs, rewrites or silently selects another head.
  echo "PASS application recovery startup: explicit trusted files, parsed policies, exact canonical selection and no fallback"
try:
  main() # Native/fixture errors cannot yield a partially configured service.
except:
  quit(2)
