# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic report payload/failure guards preserve a genuine complete-source explicit-profile control.
import std/[assertions, cmdline, syncio]
import ../support/[state_inventory_context, service_deposit_context, economic_profile_context]
import ../../src/chain/parameters
import ../../src/state/[economics_table, economic_profile, footprint_audit, service_directory]
import ../../src/codec/bounded
include composition_fixture
proc extract(outcome: EconomicsTableResult[StateEconomicsTable]): StateEconomicsTable {.noinline.} =
  ## No default or failed report grants completed source-bearing observations.
  outcome.value
proc guardreason(outcome: EconomicsTableResult[StateEconomicsTable]) {.noinline.} =
  ## Default reports do not invent a failed row reason.
  discard outcome.observationFailure
proc guardservice(outcome: EconomicsTableResult[StateEconomicsTable]) {.noinline.} =
  ## Default reports do not invent a failed row service.
  discard outcome.failedService
proc guardordinal(outcome: EconomicsTableResult[StateEconomicsTable]) {.noinline.} =
  ## Default reports do not invent a failed row ordinal.
  discard outcome.failedOrdinal
case paramStr(1)
of "default": discard extract(default(EconomicsTableResult[StateEconomicsTable])) # No default report.
of "invalid": discard extract(buildEconomicsTable(default(CheckedAccountFootprints), default(
    StateServiceDirectory), default(StateEconomicProfile), EconomicsTableLimits())) # Actual evidence refusal.
of "reason": guardreason(default(EconomicsTableResult[StateEconomicsTable])) # No default failed row.
of "service": guardservice(default(EconomicsTableResult[StateEconomicsTable])) # No default failed row.
of "ordinal": guardordinal(default(EconomicsTableResult[StateEconomicsTable])) # No default failed row.
of "ok":
  let source = depositTestSource(compositionFixture(paramStr(2)), inventoryServices())
  let profile = captureEconomicProfile(decodeParameters(economicTestWire()).value).value
  let table = extract(buildEconomicsTable(source.footprints, source.directory, profile,
      EconomicsTableLimits(services: ElementLimit(2), bytes: ByteLimit(4096))))
  assert table.economicTableInfo.value.services == 2
  echo "state-economics-table-results: ok"
else: quit(2) # Unknown selectors cannot satisfy controls.
