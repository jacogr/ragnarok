# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict atomic assured chain result and receipt guards with actual success and genuine late failures.

import std/[assertions, cmdline]
import ../../src/state/assured/[chain as assured_chain, composition as assured_composition]
import ../../src/state/store
import ../../src/chain/[genesis, provider, parameters]
import ../../src/codec/state/layout as state_layout
import ../support/[pvm_assured_chain, pvm_computed_chain]

proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Cause real child capture failure after private publication, preserving both live handles.
proc expect[T](outcome: AssuredChainResult[T], reason: AssuredChainError) =
  ## Confirm selected alternatives opaquely so runtime misuse is not a static contradiction.
  assert outcome.error == reason, "assured chain runtime control"
let source = assuredChainFixture()
let seed = source.assuredChainSeed
let parent = seed.view.bestBlock.value
let original = seed.state.snapshot.value
var state = seed.state
var view = seed.view
let done = advanceAssuredChain(state, view, source)
expect(done, AssuredChainError.None)
assert done.value.assuredChainBlock.value.slot == 3 and view.retainedCount == 3
let stale = advanceAssuredChain(state, view, source)
expect(stale, AssuredChainError.StaleState)
var fresh = seed.state
var freshView = seed.view
let invalid = advanceAssuredChain(fresh, freshView, default(ComposedAssuredState))
expect(invalid, AssuredChainError.InvalidSource)
var absentState = default(StateStore)
let missingState = advanceAssuredChain(absentState, freshView, source)
expect(missingState, AssuredChainError.StateFailure)
assert missingState.stateError == StateStoreError.Uninitialized
var absentView = default(ChainView)
let missingView = advanceAssuredChain(fresh, absentView, source)
expect(missingView, AssuredChainError.UninitializedView)
var equalRoot = seed.state
let chapter = chapterKey(StateChapter(13))
assert equalRoot.apply([StateWrite(kind: StateWriteKind.Put, key: chapter, value: original.lookup(
    chapter).value.bytes)]).error == StateStoreError.None
var staleView = genesisView(captureBlockSnapshot(chainHeaderBytes(parent.header),
    equalRoot.snapshot.value, source.assuredCompositionParameters.value))
let staleHead = advanceAssuredChain(fresh, staleView, source)
expect(staleHead, AssuredChainError.StaleView)
var parameterWire = source.assuredCompositionParameters.value.encodeParameters
parameterWire[58] = parameterWire[58] xor 1
var wrongParameters = genesisView(captureBlockSnapshot(chainHeaderBytes(parent.header), original,
    decodeParameters(parameterWire).value))
let mismatch = advanceAssuredChain(fresh, wrongParameters, source)
expect(mismatch, AssuredChainError.ParametersMismatch)
failHash(1)
let late = advanceAssuredChain(fresh, freshView, source)
expect(late, AssuredChainError.CaptureFailure)
assert late.captureError == GenesisError.Invalid
failHash(0)
var otherHeader = chainHeaderBytes(parent.header)
otherHeader[0] = otherHeader[0] xor 1
var wrongParent = genesisView(captureBlockSnapshot(otherHeader, original,
    source.assuredCompositionParameters.value))
let notChild = advanceAssuredChain(fresh, wrongParent, source)
expect(notChild, AssuredChainError.ViewFailure)
assert notChild.viewError == ViewAdvanceError.NotChild
let missing = default(AssuredChainResult[AdvancedAssuredChain])
case paramStr(1)
of "default": discard missing.value # Only selected complete success or its actual refused cause permits extraction.
of "source": discard invalid.value # Only selected complete success or its actual refused cause permits extraction.
of "stale": discard stale.value # Only selected complete success or its actual refused cause permits extraction.
of "state": discard missingState.value # Only selected complete success or its actual refused cause permits extraction.
of "view": discard missingView.value # Only selected complete success or its actual refused cause permits extraction.
of "stale-view": discard staleHead.value # Only selected complete success or its actual refused cause permits extraction.
of "parameters": discard mismatch.value # Only selected complete success or its actual refused cause permits extraction.
of "capture": discard late.value # Only selected complete success or its actual refused cause permits extraction.
of "child": discard notChild.value # Only selected complete success or its actual refused cause permits extraction.
of "owner": discard default(AdvancedAssuredChain).assuredChainSource.value # Only selected complete success or its actual refused cause permits extraction.
of "snapshot": discard default(AdvancedAssuredChain).assuredChainSnapshot.value # Only selected complete success or its actual refused cause permits extraction.
of "block": discard default(AdvancedAssuredChain).assuredChainBlock.value # Only selected complete success or its actual refused cause permits extraction.
of "stateError-default": discard missing.stateError # Only selected complete success or its actual refused cause permits extraction.
of "stateError-success": discard done.stateError # Only selected complete success or its actual refused cause permits extraction.
of "stateError-source": discard invalid.stateError # Only selected complete success or its actual refused cause permits extraction.
of "stateError-other": discard late.stateError # Only selected complete success or its actual refused cause permits extraction.
of "publicationFailure-default": discard missing.publicationFailure # Only selected complete success or its actual refused cause permits extraction.
of "publicationFailure-success": discard done.publicationFailure # Only selected complete success or its actual refused cause permits extraction.
of "publicationFailure-source": discard invalid.publicationFailure # Only selected complete success or its actual refused cause permits extraction.
of "publicationFailure-other": discard late.publicationFailure # Only selected complete success or its actual refused cause permits extraction.
of "headerError-default": discard missing.headerError # Only selected complete success or its actual refused cause permits extraction.
of "headerError-success": discard done.headerError # Only selected complete success or its actual refused cause permits extraction.
of "headerError-source": discard invalid.headerError # Only selected complete success or its actual refused cause permits extraction.
of "headerError-other": discard late.headerError # Only selected complete success or its actual refused cause permits extraction.
of "captureError-default": discard missing.captureError # Only selected complete success or its actual refused cause permits extraction.
of "captureError-success": discard done.captureError # Only selected complete success or its actual refused cause permits extraction.
of "captureError-source": discard invalid.captureError # Only selected complete success or its actual refused cause permits extraction.
of "captureError-other": discard notChild.captureError # Only selected complete success or its actual refused cause permits extraction.
of "viewError-default": discard missing.viewError # Only selected complete success or its actual refused cause permits extraction.
of "viewError-success": discard done.viewError # Only selected complete success or its actual refused cause permits extraction.
of "viewError-source": discard invalid.viewError # Only selected complete success or its actual refused cause permits extraction.
of "viewError-other": discard late.viewError # Only selected complete success or its actual refused cause permits extraction.
else: discard invalid.value # Unknown modes never become passing controls.
