# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused union and fulfillment results expose no private payload or partially applied map.

import std/cmdline
import ../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../src/state/accumulation_effects as state_accumulation_effects
import ../../src/state/preimages as state_preimages
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/composite as codec_composite
import ../../src/codec/owned as codec_owned
import ../../src/codec/header as codec_header
import ../support/state_accumulation_provision_integration

## Fail immutable union hashing only after genuine source contexts exist.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
let argument = paramStr(1)
let contexts = integrationContexts()
var result = prepareAccumulationProvisions(contexts, integrationPolicy())
if argument == "default":
  result = default(AccumulationProvisionResult[PreparedAccumulationProvisions]) # Select an uninitialized result dynamically.
if argument == "invalid":
  result = prepareAccumulationProvisions([default(AccumulationEffectContext)], integrationPolicy()) # Actual source refusal.
if argument == "backend":
  failHash(1)
  result = prepareAccumulationProvisions(contexts, integrationPolicy()) # Actual content-hash refusal.
  failHash(0)
case argument
of "default", "invalid", "backend":
  discard result.value
of "index":
  let index = if argument == "index": high(uint64) else: 0'u64
  discard result.value.provisionSourceAt(AccumulationProvisionSourceIndex(index)).value
of "provided-default":
  var prepared = prepareProvidedPreimages(decodeOwnedPreimages([0'u8], default(
      PreimageLimits)).value,
    default(PreimageLimits)).value
  if argument == "provided-default":
    prepared = default(PreparedPreimageValues) # Default values cannot authorize fnprovide.
  var state = newStateStore(integrationEntries(), integrationStoreLimits()).value
  discard integrateProvidedPreimages(state, prepared, HeaderSlot(7)).value
else:
  var plan = result.value
  var state = newStateStore(integrationEntries(), integrationStoreLimits()).value
  if argument == "apply-default":
    plan = default(PreparedAccumulationProvisions) # A default union is not a valid empty set.
  else:
    let request = integrationRequest(99, @[9'u8, 8, 7])
    discard state.apply([StateWrite(key: request.key, kind: StateWriteKind.Put, value: @[
        4'u8])]).value # Late malformed posterior history.
  discard integrateAccumulationProvisions(state, plan, HeaderSlot(7)).value
