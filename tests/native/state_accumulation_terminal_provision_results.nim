# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Failed/default terminal provision plans and wrong-alternative reasons refuse before extraction.

import std/cmdline
import ../../src/state/accumulation_terminal_provisions as state_accumulation_terminal_provisions
import ../../src/state/accumulation_dispatch as state_accumulation_dispatch
import ../../src/state/accumulation_provisions as state_accumulation_provisions
import ../../src/state/store as state_store
import ../../src/codec/header as codec_header
import ../../src/codec/state_trie as codec_state_trie
import ../support/state_accumulation_terminal_provisions
import ../support/state_accumulation_provision_integration
import ../support/pvm_accumulation_provision

# Fail hashing only after the actual completed guest exists.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
let argument = paramStr(1)
let execution = terminalProvisionExecution()
let slot = HeaderSlot(128)
let limits = integrationPolicy()
var result = prepareTerminalAccumulationProvisions([execution], slot, limits)
case argument
of "default":
  result = default(AccumulationTerminalProvisionResult[PreparedTerminalAccumulationProvisions])
  discard result.value
of "normalization":
  result = prepareTerminalAccumulationProvisions([default(AccumulationDispatchResult)], slot, limits)
  discard result.value
of "provision":
  failHash(1)
  result = prepareTerminalAccumulationProvisions([execution], slot, limits)
  failHash(0)
  discard result.value
of "slot":
  result = prepareTerminalAccumulationProvisions([execution], HeaderSlot(7), limits)
  discard result.value
of "index":
  let index = if argument == "index": high(uint64) else: 0'u64
  discard result.value.terminalProvisionOutcomeAt(AccumulationProvisionSourceIndex(index)).value
of "wrong-normalization":
  discard result.normalizationError
of "wrong-provision":
  discard result.provisionError
else:
  var plan = result.value
  var state = newStateStore(terminalPosteriorEntries(), integrationStoreLimits()).value
  if argument == "apply-default":
    plan = default(PreparedTerminalAccumulationProvisions) # Select invalid ownership dynamically.
  else:
    let request = provisionRequest(99, @[81'u8])
    discard state.apply([StateWrite(key: request.key, kind: StateWriteKind.Put, value: @[4'u8])]).value
  discard integrateTerminalAccumulationProvisions(state, plan).value
