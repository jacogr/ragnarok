# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic whole-table guards retain a real complete-source positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_inventory_context
import ../support/state_service_directory_context
import ../../src/state/supervision_table as state_supervision_table
import ../../src/state/service_directory as state_service_directory
import ../../src/state/inventory as state_inventory
import ../../src/codec/bounded as codec_bounded
include nimony_composition_fixture
proc extract(outcome: SupervisionTableResult[StateSupervisionTable]): StateSupervisionTable {.noinline.} =
  ## Default and bounded construction failure never expose table authority.
  outcome.value
proc reason(outcome: SupervisionTableResult[StateSupervisionTable]) {.noinline.} =
  ## Defaults do not invent a row-resolution error.
  discard outcome.resolutionError
case paramStr(1)
of "default": discard extract(default(SupervisionTableResult[StateSupervisionTable])) # No default table.
of "invalid": discard extract(buildSupervisionTable(default(StateServiceDirectory),
    SupervisionTableLimits())) # Actual source refusal.
of "reason": reason(default(SupervisionTableResult[StateSupervisionTable])) # No default nested reason.
of "ok":
  let services = inventoryServices()
  let source = captureStateInventory(inventoryManifest(compositionFixture(paramStr(2)), services),
      services, inventoryCaptureLimits).value
  let directory = buildStateServiceDirectory(source, directoryTestLimits).value
  let table = extract(buildSupervisionTable(directory, SupervisionTableLimits(
      services: ElementLimit(2), bytes: ByteLimit(4096))))
  assert table.supervisionTableInfo.value.services == 2
  echo "state-supervision-table-results: ok"
else: quit(2) # Unknown selectors cannot pass controls.
