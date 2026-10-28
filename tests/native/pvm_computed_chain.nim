# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized computed-chain result/receipt contracts with genuine success and real late-stage failures.

import std/assertions
import std/cmdline
import ../../src/state/computed_chain as state_computed_chain
import ../../src/state/computed_composition as state_computed_composition
import ../../src/state/store as state_store
import ../../src/chain/genesis as chain_genesis
import ../../src/chain/provider as chain_provider
import ../../src/chain/parameters as chain_parameters
import ../support/pvm_computed_chain
import ../support/pvm_computed_state_publication

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Cause actual late child capture failure after private publication.
proc expect[T](outcome: ComputedChainResult[T], reason: ComputedChainError) =
  ## Confirm selection opaquely so intentional runtime misuse is not folded into static contradictions.
  assert outcome.error == reason, "computed chain runtime control"
let source = chainFixture()
let parent = source.chainFixtureParent(source.chainFixtureParameters)
assert parent.error == GenesisError.None
let initial = genesisView(parent)
var state = forkStateStore(parent.value.stateSnapshot).value
var view = initial
let done = advanceComputedChain(state, view, source)
expect(done, ComputedChainError.None)
assert done.value.computedChainBlock.value.slot == 2
let stale = advanceComputedChain(state, view, source)
expect(stale, ComputedChainError.StaleState)
var fresh = forkStateStore(parent.value.stateSnapshot).value
var freshView = initial
let invalid = advanceComputedChain(fresh, freshView, default(ComposedComputedState))
expect(invalid, ComputedChainError.InvalidSource)
var empty = default(StateStore)
let missingState = advanceComputedChain(empty, freshView, source)
expect(missingState, ComputedChainError.StateFailure)
assert missingState.stateError == StateStoreError.Uninitialized
var absentView = default(ChainView)
let missingView = advanceComputedChain(fresh, absentView, source)
expect(missingView, ComputedChainError.UninitializedView)
var parameterWire = source.chainFixtureParameters.encodeParameters
parameterWire[58] = parameterWire[58] xor 1
var otherParameters = genesisView(source.chainFixtureParent(decodeParameters(parameterWire).value))
let mismatch = advanceComputedChain(fresh, otherParameters, source)
expect(mismatch, ComputedChainError.ParametersMismatch)
failHash(1)
let late = advanceComputedChain(fresh, freshView, source)
expect(late, ComputedChainError.CaptureFailure)
assert late.captureError == GenesisError.Invalid
failHash(0)
var otherHeader = chainHeaderBytes(parent.value.header)
otherHeader[0] = otherHeader[0] xor 1
var otherParent = genesisView(captureBlockSnapshot(otherHeader, source.statePublicationParent,
    source.chainFixtureParameters))
let notChild = advanceComputedChain(fresh, otherParent, source)
expect(notChild, ComputedChainError.ViewFailure)
assert notChild.viewError == ViewAdvanceError.NotChild
let missing = default(ComputedChainResult[AdvancedComputedChain])
case paramStr(1)
of "default": discard missing.value # A refused/default phase carries no installed child.
of "source": discard invalid.value # A refused/default phase carries no installed child.
of "stale": discard stale.value # A refused/default phase carries no installed child.
of "state": discard missingState.value # A refused/default phase carries no installed child.
of "view": discard missingView.value # A refused/default phase carries no installed child.
of "parameters": discard mismatch.value # A refused/default phase carries no installed child.
of "capture": discard late.value # A refused/default phase carries no installed child.
of "child": discard notChild.value # A refused/default phase carries no installed child.
of "owner": discard default(AdvancedComputedChain).computedChainPublication.value # Default receipt has no computed publication.
of "block": discard default(AdvancedComputedChain).computedChainBlock.value # Default receipt has no captured child.
of "stateError-default": discard missing.stateError # Only the selected cause is readable.
of "stateError-success": discard done.stateError # Only the selected cause is readable.
of "stateError-source": discard invalid.stateError # Only the selected cause is readable.
of "publicationFailure-default": discard missing.publicationFailure # Only the selected cause is readable.
of "publicationFailure-success": discard done.publicationFailure # Only the selected cause is readable.
of "publicationFailure-source": discard invalid.publicationFailure # Only the selected cause is readable.
of "headerError-default": discard missing.headerError # Only the selected cause is readable.
of "headerError-success": discard done.headerError # Only the selected cause is readable.
of "headerError-source": discard invalid.headerError # Only the selected cause is readable.
of "captureError-default": discard missing.captureError # Only the selected cause is readable.
of "captureError-success": discard done.captureError # Only the selected cause is readable.
of "captureError-source": discard invalid.captureError # Only the selected cause is readable.
of "viewError-default": discard missing.viewError # Only the selected cause is readable.
of "viewError-success": discard done.viewError # Only the selected cause is readable.
of "viewError-source": discard invalid.viewError # Only the selected cause is readable.
of "state-capture": discard late.stateError # A real capture failure carries no store cause.
of "capture-view": discard notChild.captureError # A real append failure carries no capture cause.
of "view-capture": discard late.viewError # A real capture failure carries no append cause.
else: discard invalid.value # Unknown modes never become passing controls.
