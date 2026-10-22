# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Current request-length reservation boundaries remain finite complete-account facts without allocating absent advertised payloads.
import std/[assertions, envvars, syncio]
import ../../support/[state_inventory_context, economic_profile_context]
import ../../../src/chain/parameters
import ../../../src/state/[inventory, account_audit_plan, account_audit, account_invariants,
  footprint_audit,
  preimage_content, preimage_linkage, service_directory, economic_profile, economics_table]
import ../../../src/codec/[bounded, state_accounts, state_composition, state_requests]
include ../../native/composition_fixture
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Disable hashing after exact complete source capture for each advertised length.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## No absent content may be copied or hashed merely because its request advertises a large length.
const limits = AccountAuditLimits(planning: ElementLimit(2),
  footprints: FootprintAuditLimits(services: ElementLimit(1), checks: ElementLimit(2)),
  content: PreimageContentLimits(services: ElementLimit(1)),
  linkage: PreimageLinkageLimits(services: ElementLimit(1)))
proc main() {.raises.} =
  ## Fixed account metadata reserves exact footprint across current canonical small/maximal request lengths.
  let fixture = compositionFixture(getEnv("RAGNAROK_COMPOSITION_FIXTURE"))
  let hash = inventoryServices()[0].preimages[0].hash
  let profile = captureEconomicProfile(decodeParameters(economicTestWire()).value).value
  var descriptors = 0'u64
  for length in [0'u32, 1, 127, 128, 0xfffffffc'u32, 0xfffffffd'u32]:
    let octets = 81'u64+uint64(length)
    let minimum = 104'u64+3*octets # Independent safe direct equation with two request items and rates100/2/3.
    let services = @[StateService(service: ServiceIndex(7), metadata: ServiceMetadata(
        balance: AccountBalance(minimum),
      storageItems: AccountStorageItems(2), storageBytes: AccountStorageBytes(octets),
          supervisor: ServiceIndex(7), supervisorCreated: AccountSlot(2), created: AccountSlot(2)),
      requests: @[StateRequestItem(hash: hash, length: RequestLength(length),
          history: requestedHistory())])]
    fail(0)
    let source = captureStateInventory(inventoryManifest(fixture, services), services,
        inventoryCaptureLimits).value
    if descriptors == 0:
      descriptors = source.inventoryInfo.value.descriptorBytes # Save exact fixed descriptor accounting from the first genuine capture.
    else:
      assert source.inventoryInfo.value.descriptorBytes ==
          descriptors # Advertised payload extent does not grow retained fixed request descriptors.
    fail(1)
    let plan = planAccountAudit(source, limits).value
    assert plan.accountPlanInfo.value.contentBytes == 0 and plan.accountPlanInfo.value.preimages == 0
    let audited = executeAccountAudit(plan).value
    assert audited.accountInvariantInfo.value.content.preimages == 0
    let footprints = auditAccountFootprints(source, limits.footprints).value
    let directory = buildStateServiceDirectory(source, ServiceDirectoryLimits(
        services: ElementLimit(1), bytes: ByteLimit(4096))).value
    let table = buildEconomicsTable(footprints, directory, profile, EconomicsTableLimits(
        services: ElementLimit(1), bytes: ByteLimit(4096))).value
    assert uint64(table.economicsFor(ServiceIndex(7)).value.minimum) == minimum
    assert table.economicsFor(ServiceIndex(7)).value.covered
    if length == 0xfffffffd'u32:
      assert octets == 4294967374'u64 and minimum ==
          12884902226'u64 # Authored maximal-domain reservation witness remains within E8.
    assert calls() == 0
    fail(0)
  fail(1)
  for reserved in [0xfffffffe'u32, 0xffffffff'u32]:
    let rejected = serviceRequestEntry(ServiceIndex(7), hash, RequestLength(reserved),
        requestedHistory(),
      RequestEntryConfig(keyBytes: ByteLimit(32), history: RequestHistoryConfig(items: ElementLimit(
          3), maxBytes: ByteLimit(13))))
    assert rejected.error == RequestError.InvalidLength # Both current reserved namespace prefixes refuse before hashing.
  assert calls() == 0
  fail(0)
  echo "state-account-request-boundaries: ok (6 valid, 2 reserved)"
try:
  main()
except:
  quit(2) # Setup failure cannot qualify current request reservation or bounded payload work.
