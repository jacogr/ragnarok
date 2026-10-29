# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual Services startup seeds preserve physical source ownership, detached caller keys and exact stage refusals.
import std/[assertions, envvars, syncio]
import std/posix/posix
import ../../support/[current_repeated_logical_context, collected_logical_services_context,
    parent_profile_context, parent_globals_context, supplied_logical_context]
import ../../../src/app/services
import ../../../src/app/logical/seed as logical_seed
import ../../../src/app/chain
import ../../../src/state/parent/[logical as parent_logical, globals as parent_globals,
    profile as parent_profile]
import ../../../src/state/supplied/logical_inventory as supplied_logical_inventory
import ../../../src/state/[inventory, manifest, store, global_snapshot]
import ../../../src/codec/[report_owned, bounded]
import ../../../src/codec/state/composition as state_composition
proc main() {.raises.} =
  ## The complete signed source is reparsed by Services before the new host API captures its own seed.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = repeatedLogicalFixture(decodeOwnedReport(bytes, 2).value)
  var owner = default(Services)
  var path = "application-logical-seed-chain.json"
  let old = startLogicalServices(owner, fixture, path)
  defer:
    owner.close()
    discard posix.unlink(path.toCString())
  let limits = LogicalSeedLimits(profile: parentProfileTestLimits, globals: parentGlobalsTestLimits,
    logical: suppliedLogicalTestLimits)
  var declarations = fixture.first.services
  let result = owner.captureLogicalSeed(declarations, limits)
  assert result.error == LogicalSeedError.None
  let captured = result.value.logicalParentInventory.value
  assert sameStateSnapshot(captured.suppliedInventory.value.inventorySource.value.manifestSource.value,
      owner.stateSnapshot.value)
  assert sameStateSnapshot(old.logicalParentInventory.value.suppliedInventory.value.inventorySource.value.manifestSource.value,
      owner.stateSnapshot.value)
  declarations[0].storage[0].key.add(200'u8)
  assert owner.captureLogicalSeed(declarations, limits).error == LogicalSeedError.LogicalFailure
  assert captured.suppliedLogicalInfo.value.rawKeyBytes > 0, "captured keys survive caller mutation"
  var short = limits
  short.profile.blocks = ElementLimit(0)
  assert owner.captureLogicalSeed(fixture.first.services, short).profileFailure.error ==
      ParentProfileError.LimitExceeded
  short = limits
  short.profile.viewBytes = ByteLimit(0)
  assert owner.captureLogicalSeed(fixture.first.services, short).profileFailure.error ==
      ParentProfileError.LimitExceeded
  let direct = initApplicationChain(owner.chainView).value
  let profile = direct.captureParentProfile(limits.profile).value
  assert sameStateSnapshot(profile.parentContext.value.state, owner.stateSnapshot.value)
  assert direct.captureParentProfile(short.profile).error == ParentProfileError.LimitExceeded
  short = limits
  short.globals.totalBytes = ByteLimit(0)
  assert owner.captureLogicalSeed(fixture.first.services,
      short).globalsFailure.globalFailure.error == GlobalStateError.LimitExceeded
  short = limits
  short.logical.keys = ElementLimit(0)
  assert owner.captureLogicalSeed(fixture.first.services, short).error ==
      LogicalSeedError.LogicalFailure
  let missing = captureLogicalSeed(default(ApplicationChain), [], limits)
  assert missing.profileFailure.error == ParentProfileError.MissingHead
  echo "application-logical-seed: ok"
try:
  main()
except:
  quit(2) # Native setup failures cannot satisfy selected-source qualification.
