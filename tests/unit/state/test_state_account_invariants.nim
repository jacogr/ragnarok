# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Same-capture joins reject equal-source substitutions and defaults without rehashing certified evidence.
# @@Verification={"arc": "state_account_invariants_arc_release"}
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, account_invariant_context, arc_evidence]
import ../../../src/state/[account_invariants, inventory, footprint_audit, preimage_content, preimage_linkage]
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Disable all hashing after generating real independently bounded certificates.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Joining and owner comparisons must not hash or rebuild a source.
proc cycle(footprints: CheckedAccountFootprints, content: CheckedPreimageContent,
    linkage: CheckedPreimageLinkage) =
  ## Retire one joined handle and its successful source extraction before observation.
  let checked = joinAccountInvariants(footprints, content, linkage).value
  assert checked.accountInvariantInfo.value.content.bytes == 3
  assert sameStateInventory(checked.accountInvariantInventory.value,
      footprints.footprintInventory.value)
proc main() {.raises.} =
  ## Separate captures of the same complete source intentionally have different logical identities.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  let services = inventoryServices()
  let manifest = inventoryManifest(fixture, services)
  let source = captureStateInventory(manifest, services, inventoryCaptureLimits).value
  let other = captureStateInventory(manifest, services, inventoryCaptureLimits).value
  let independent = captureStateInventory(inventoryManifest(fixture, services), services,
      inventoryCaptureLimits).value
  assert sameStateInventory(source, source)
  let copied = source
  assert sameStateInventory(source, copied)
  assert not sameStateInventory(source, other) and not sameStateInventory(source, independent)
  assert not sameStateInventory(default(StateInventory), default(StateInventory))
  let footprints = auditAccountFootprints(source, invariantFootprintLimits).value
  let content = auditPreimageContent(source, invariantContentLimits).value
  let linkage = auditPreimageLinkage(source, invariantLinkageLimits).value
  let otherContent = auditPreimageContent(other, invariantContentLimits).value
  let otherLinkage = auditPreimageLinkage(independent, invariantLinkageLimits).value
  fail(1)
  let result = joinAccountInvariants(footprints, content, linkage)
  assert result.error == AccountInvariantError.None
  assert sameStateInventory(result.value.accountInvariantInventory.value, source)
  assert result.value.accountInvariantInfo.value.footprints.checks == 4
  assert result.value.accountInvariantInfo.value.linkage.comparisons == 1
  assert joinAccountInvariants(default(CheckedAccountFootprints), content, linkage).error ==
      AccountInvariantError.InvalidFootprints
  assert joinAccountInvariants(footprints, default(CheckedPreimageContent), linkage).error ==
      AccountInvariantError.InvalidContent
  assert joinAccountInvariants(footprints, content, default(CheckedPreimageLinkage)).error ==
      AccountInvariantError.InvalidLinkage
  assert joinAccountInvariants(footprints, otherContent, linkage).error ==
      AccountInvariantError.SourceMismatch
  assert joinAccountInvariants(footprints, content, otherLinkage).error ==
      AccountInvariantError.SourceMismatch
  assert default(CheckedAccountInvariants).accountInvariantInfo.error ==
      AccountInvariantError.Uninitialized
  assert default(CheckedAccountInvariants).accountInvariantInventory.error ==
      AccountInvariantError.Uninitialized
  for i in 0..<25: cycle(footprints, content, linkage) # Warm the constant retained-owner path.
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(footprints, content, linkage) # Joins retire without accumulating evidence owners.
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_account_invariants", 1000, before, finalBytes)
  fail(0)
  echo "state-account-invariants: ok"
try:
  main()
except:
  quit(2) # Independent fixture failure never qualifies a join.
