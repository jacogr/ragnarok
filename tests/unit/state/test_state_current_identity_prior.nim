# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Completed-origin current logical parents retain exact previous producer/view and cannot be projected as configured startup parents.
# @@Verification={"arc":"state_current_identity_prior_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[current_repeated_logical_context, current_identity_context, arc_evidence]
import ../../../src/state/[current_identities, parent_logical, current_logical, current_state,
    supplied_logical_inventory, inventory, manifest, store, accumulation_current_update]
import ../../../src/codec/[bounded, report_owned]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Both genuine current children and the first full matching finish before hash-free original-source/identity tests.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Completed-source normalization, view/key checks and source extraction cannot hash.
proc cycle(source: CurrentLogicalState, update: PreparedCurrentChainUpdate) =
  ## Retire admitted full history/index copies and completed-origin current aliases without retaining an unchecked parent prefix.
  let kept = preserveCurrentIdentities(source, update, currentIdentityTestLimits).value
  assert kept.identityInfo.value.entries == 34 and kept.identityParent.error ==
      CurrentIdentityError.WrongSource
proc main() {.raises.} =
  ## Maintained authoring produces only the actual next empty block; actual current candidate owns every prepared result.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let base = decodeOwnedReport(bytes, 2).value
  let fixture = repeatedLogicalFixture(base)
  let foreign = repeatedLogicalFixture(base)
  fail(1)
  let preserved = preserveCurrentIdentities(fixture.logical, fixture.next,
      currentIdentityTestLimits).value
  assert preserved.identityInfo.value.entries == 34 and preserved.identityInfo.value.keyChecks == 68
  assert preserved.identityParent.error == CurrentIdentityError.WrongSource
  let prior = preserved.identityPriorCurrent.value
  assert sameStateInventory(prior.currentLogicalInventory.value.suppliedInventory.value,
      fixture.logical.currentLogicalInventory.value.suppliedInventory.value)
  assert sameStateInventory(preserved.identityLogical.value.suppliedInventory.value,
      fixture.logical.currentLogicalInventory.value.suppliedInventory.value)
  assert sameStateSnapshot(preserved.identityUpdate.value.currentUpdatePriorState,
      fixture.first.update.currentUpdateState)
  assert sameStateSnapshot(preserved.identityUpdate.value.currentUpdateState,
      fixture.next.currentUpdateState)
  let configured = preserveCurrentIdentities(fixture.first.parent, fixture.first.update,
      currentIdentityTestLimits).value
  assert configured.identityParent.error == CurrentIdentityError.None and
      configured.identityPriorCurrent.error == CurrentIdentityError.WrongSource
  assert preserveCurrentIdentities(default(CurrentLogicalState), fixture.next,
      currentIdentityTestLimits).error == CurrentIdentityError.InvalidParent
  assert preserveCurrentIdentities(fixture.logical, default(PreparedCurrentChainUpdate),
      currentIdentityTestLimits).error == CurrentIdentityError.InvalidUpdate
  assert preserveCurrentIdentities(foreign.logical, fixture.next,
      currentIdentityTestLimits).error == CurrentIdentityError.ParentMismatch
  var exact = currentIdentityTestLimits
  exact.keys = ElementLimit(68)
  exact.blocks = ElementLimit(10)
  exact.viewBytes = ByteLimit(preserved.identityInfo.value.viewBytes)
  assert preserveCurrentIdentities(fixture.logical, fixture.next, exact).error ==
      CurrentIdentityError.None
  var short = exact
  short.keys = ElementLimit(67)
  assert preserveCurrentIdentities(fixture.logical, fixture.next, short).error ==
      CurrentIdentityError.LimitExceeded
  short = exact
  short.blocks = ElementLimit(9)
  assert preserveCurrentIdentities(fixture.logical, fixture.next, short).error ==
      CurrentIdentityError.LimitExceeded
  short = exact
  short.viewBytes = ByteLimit(uint64(exact.viewBytes)-1)
  assert preserveCurrentIdentities(fixture.logical, fixture.next, short).error ==
      CurrentIdentityError.LimitExceeded
  assert calls() == 0
  for i in 0..<25: cycle(fixture.logical, fixture.next)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(fixture.logical, fixture.next)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_current_identity_prior", 1000, before, finalBytes)
  fail(0)
  echo "state-current-identity-prior: ok"
try:
  main()
except:
  quit(2) # Genuine current continuation and source-kind selection cannot be fabricated from equal roots or default owners.
