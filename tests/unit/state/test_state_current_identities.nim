# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine exact-original predecessor/full-view binding and hash-free complete sorted physical identity observations.
# @@Verification={"arc":"state_current_identities_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[accumulation_current_chain_context, current_checkpoint_context,
    parent_logical_context, current_identity_context, arc_evidence]
import ../../../src/state/current/identities as current_identities
import ../../../src/state/parent/[logical as parent_logical, globals as parent_globals,
    profile as parent_profile]
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/store
import ../../../src/chain/[provider, genesis]
import ../../../src/codec/[bounded, report_owned]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Prepare real updates and full supplied matching before disabling all hashes.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Full view/identity comparison never rehashes state or namespace keys.
proc cycle(parent: SelectedLogicalParent, update: PreparedCurrentChainUpdate) =
  ## Retire fixed identity observations and admitted full view/index copies on every cycle.
  assert preserveCurrentIdentities(parent, update,
      currentIdentityTestLimits).value.identityInfo.value.entries == 18
proc main() {.raises.} =
  ## Same original parent bytes can yield distinct immutable owners; explicit finality also distinguishes original selections.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let fixture = currentChainFixture(base, completeState = true)
  let parent = selectedLogicalParent(fixture.currentChainSeeded).value
  let update = currentCheckpointPrepared(fixture)
  let absent = currentCheckpointPrepared(fixture, finalized = false)
  let other = currentChainFixture(base, completeState = true)
  let foreign = selectedLogicalParent(other.currentChainSeeded).value
  fail(1)
  let kept = preserveCurrentIdentities(parent, update, currentIdentityTestLimits).value
  assert kept.identityInfo.value.entries == 18 and kept.identityInfo.value.keyChecks == 36
  assert sameStateSnapshot(kept.identityUpdate.value.currentUpdateState, update.currentUpdateState)
  assert sameChainView(kept.identityParent.value.logicalParentGlobals.value.parentGlobalsProfile.value.copyParentView(
      currentIdentityTestLimits.viewBytes).value, fixture.currentChainSeeded)
  assert preserveCurrentIdentities(foreign, update, currentIdentityTestLimits).error ==
      CurrentIdentityError.ParentMismatch
  assert preserveCurrentIdentities(parent, absent, currentIdentityTestLimits).error ==
      CurrentIdentityError.ViewMismatch
  assert preserveCurrentIdentities(default(SelectedLogicalParent), update,
      currentIdentityTestLimits).error == CurrentIdentityError.InvalidParent
  assert preserveCurrentIdentities(parent, default(PreparedCurrentChainUpdate),
      currentIdentityTestLimits).error == CurrentIdentityError.InvalidUpdate
  var exact = currentIdentityTestLimits
  exact.keys = ElementLimit(36)
  exact.blocks = ElementLimit(7)
  exact.viewBytes = ByteLimit(kept.identityInfo.value.viewBytes)
  assert preserveCurrentIdentities(parent, update, exact).error == CurrentIdentityError.None
  var short = exact
  short.keys = ElementLimit(35)
  assert preserveCurrentIdentities(parent, update, short).error ==
      CurrentIdentityError.LimitExceeded
  short = exact
  short.blocks = ElementLimit(6)
  assert preserveCurrentIdentities(parent, update, short).error ==
      CurrentIdentityError.LimitExceeded
  short = exact
  short.viewBytes = ByteLimit(uint64(exact.viewBytes)-1)
  assert preserveCurrentIdentities(parent, update, short).error ==
      CurrentIdentityError.LimitExceeded
  assert calls() == 0
  for i in 0..<25: cycle(parent, update)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(parent, update)
  let after = getOccupiedMem()
  assert before == after and calls() == 0
  recordArcRelease("state_current_identities", 1000, before, after)
  fail(0)
  echo "state-current-identities: ok"
try:
  main()
except:
  quit(2) # Invalid original matching or actual current preparation never becomes preserved identity evidence.
