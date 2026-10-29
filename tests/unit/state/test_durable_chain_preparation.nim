# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fallible preparation cannot publish; assignment-only installation requires exact original state and history.
import std/[assertions, envvars, syncio]
import ../../support/[durable_chain_context, accumulation_completion_context]
import ../../../src/state/store
import ../../../src/state/accumulation/[publication as accumulation_publication,
    chain as accumulation_chain]
import ../../../src/chain/[genesis, provider]
import ../../../src/codec/report_owned
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse all hashing after preparation to prove installation cannot repeat fallible work.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe both preflight and assignment-only publication independently.
proc main() {.raises.} =
  ## Genuine signed execution certificates retain exact original parent ownership through preparation.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var wire = newSeq[byte](raw.len)
  for index in 0..<raw.len: wire[index] = byte(raw[index])
  let fixture = durableFixture(decodeOwnedReport(wire, 2).value)
  let base = fixture.parent.value.stateSnapshot
  var state = base.forkStateStore.value
  var view = genesisView(fixture.parent)
  let before = view
  let policy = completionLimits().composition
  reset(1)
  let refused = prepareChainUpdate(state, view, fixture.source, policy)
  assert refused.error == ChainPreparationError.ChainFailure
  assert sameStateSnapshot(base, state.snapshot.value) and sameChainView(before, view)
  reset(0)
  let prepared = prepareChainUpdate(state, view, fixture.source, policy).value
  assert prepared.ready and sameStateSnapshot(base, state.snapshot.value) and sameChainView(view, before)
  assert prepared.chainView.retainedCount == 2 and prepared.child.slot > fixture.parent.value.slot
  let finalized = view.finalizeView(fixture.parent.value.blockHash).value
  let empty = default(PreparedChainUpdate)
  reset(1)
  assert canInstallChainUpdate(state, view, prepared)
  assert not canInstallChainUpdate(state, finalized, prepared)
  assert not canInstallChainUpdate(state, view, empty)
  installChainUpdate(state, view, prepared)
  assert calls() == 0
  assert sameStateSnapshot(state.snapshot.value, prepared.stateSnapshot)
  assert sameChainView(view, prepared.chainView) and not canInstallChainUpdate(state, view, prepared)
  assert sameStateSnapshot(base, before.bestBlock.value.stateSnapshot)
  reset(0)
  # Explicit finality retained by the original view survives staged composition and installation.
  var second = base.forkStateStore.value
  var selected = finalized
  let finalUpdate = prepareChainUpdate(second, selected, fixture.source, policy).value
  reset(1)
  installChainUpdate(second, selected, finalUpdate)
  assert calls() == 0 and sameStateSnapshot(selected.finalizedBlock.value.stateSnapshot, base)
  reset(0)
try:
  main()
except:
  quit(2) # Missing/invalid pinned fixtures cannot produce a passing preparation witness.
echo "PASS durable chain preparation: real certificates, exact parent/finality and hash-free installation"
