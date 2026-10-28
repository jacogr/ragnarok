# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise every required account/provision hash without assuming whole-map reconstruction.
## Exposes assertBatchHashRollback for observer-linked creation/deletion publication witnesses.
import std/assertions
import ../../src/state/accumulation_batch as state_accumulation_batch
import ../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../src/state/accumulation_terminal_provisions as state_accumulation_terminal_provisions
import ../../src/state/store as state_store

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset the observer before measuring a real successful publication.
proc hashAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse one required hash after the measured successful prefix.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count the actual incremental path rather than a separately rebuilt full map.

proc assertBatchHashRollback*(source: StateStore, plan: PreparedAccumulationBatch) =
  ## Refuse each real hash in turn, require both private phases and preserve the exact prior owner.
  let prior = source.snapshot.value
  var completed = source
  reset(0)
  assert applyAccumulationBatch(completed, plan).error == AccumulationBatchError.None,
    "failure calibration requires a real successful publication"
  let hashes = hashCalls()
  assert hashes > 0, "the selected publication must require backend work"
  var accountFailure = false
  var provisionFailure = false
  for successful in 0..<int(hashes):
    # Every attempt starts from the same immutable version, including after a previous late refusal.
    var candidate = source
    hashAfter(cint(successful))
    let refused = applyAccumulationBatch(candidate, plan)
    case refused.error
    of AccumulationBatchError.StoreFailure:
      # A failed account hash cannot be reclassified as a terminal refusal or expose a candidate.
      assert refused.storeError == StateStoreError.BackendFailure
      accountFailure = true
    of AccumulationBatchError.TerminalFailure:
      # Guard nested payload access by the actual alternatives before inspecting backend failure.
      assert refused.terminalError == AccumulationTerminalProvisionError.ProvisionFailure
      assert refused.provisionError == AccumulationProvisionError.BackendFailure
      provisionFailure = true
    else:
      assert false, "every required hash refusal must reject the publication"
    reset(0)
    assert sameStateSnapshot(prior, candidate.snapshot.value),
      "early and late refusals preserve the exact prior owner and every retained byte"
  assert accountFailure and provisionFailure,
    "both account-root and later provision-root failures must be exercised"
  assert sameStateSnapshot(prior, source.snapshot.value),
    "calibration and failure sweeps cannot publish into the original store"
