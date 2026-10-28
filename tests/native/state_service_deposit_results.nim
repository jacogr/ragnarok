# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic economic payload/reason guards preserve a genuine source-bound positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_inventory_context
import ../support/state_service_deposit_context
import ../../src/state/service_deposit as state_service_deposit
import ../../src/state/footprint_audit as state_footprint_audit
import ../../src/state/service_directory as state_service_directory
import ../../src/codec/state_accounts as codec_state_accounts
include nimony_composition_fixture
proc extract(outcome: ServiceDepositResult[ServiceDepositObservation]): ServiceDepositObservation {.noinline.} =
  ## Default or failed queries never expose retained economic evidence.
  outcome.value
proc reason(outcome: ServiceDepositResult[ServiceDepositObservation]) {.noinline.} =
  ## Defaults do not invent an arithmetic reason.
  discard outcome.arithmeticError
case paramStr(1)
of "default": discard extract(default(ServiceDepositResult[ServiceDepositObservation])) # No default payload.
of "reason": reason(default(ServiceDepositResult[ServiceDepositObservation])) # No default arithmetic failure.
of "invalid": discard extract(observeServiceDeposit(default(CheckedAccountFootprints), default(
    StateServiceDirectory), ServiceIndex(7), depositTestSchedule)) # Actual source refusal.
of "ok":
  let source = depositTestSource(compositionFixture(paramStr(2)), inventoryServices())
  let selected = extract(observeServiceDeposit(source.footprints, source.directory, ServiceIndex(7),
      depositTestSchedule))
  assert uint64(selected.serviceDepositInfo.value.minimum) == 469
  echo "state-service-deposit-results: ok"
else: quit(2) # Unknown selectors cannot pass controls.
