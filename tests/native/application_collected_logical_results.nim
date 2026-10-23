# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Every failed/default extraction must trigger its exact supported contract.
import std/[cmdline, assertions]
import ../../src/app/[current_logical, preparation_worker, chain]
import ../../src/state/parent_logical
proc main() =
  ## Default and wrong-stage results grant neither logical state nor a typed unrelated reason.
  let mode = paramStr(1)
  let empty = default(CollectedLogicalResult)
  case mode
  of "value": discard empty.value # This accessor requires its actual successful or failed stage.
  of "preparationFailure": discard empty.preparationFailure # This accessor requires its actual successful or failed stage.
  of "identityFailure": discard empty.identityFailure # This accessor requires its actual successful or failed stage.
  of "requestFailure": discard empty.requestFailure # This accessor requires its actual successful or failed stage.
  of "reconstructionFailure": discard empty.reconstructionFailure # This accessor requires its actual successful or failed stage.
  of "qualificationFailure": discard empty.qualificationFailure # This accessor requires its actual successful or failed stage.
  of "refreshFailure": discard empty.refreshFailure # This accessor requires its actual successful or failed stage.
  else:
    let receipt = default(PreparationCompletion)
    let source = default(SelectedLogicalParent)
    let chain = default(ApplicationChain)
    let reason = refreshCollectedLogical(chain, receipt, source, default(CollectedLogicalLimits))
    assert reason.error == CollectedLogicalError.NoCompletion # Positive control cannot require canonical state.
main()
