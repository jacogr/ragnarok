# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and missing-head application results expose no owner or unselected nested stage causes.

import std/cmdline
import ../../src/app/chain as app_chain
import ../../src/chain/provider as chain_provider

let argument = paramStr(1)
let outcome = if argument == "default": default(ApplicationChainResult[ApplicationChain])
  else: initApplicationChain(default(ChainView))
case argument
of "state": discard outcome.stateError # Missing heads authorize no successful fork or state reason.
of "chain": discard outcome.chainFailure # Constructor refusal cannot carry an application-stage failure.
of "rpc": discard outcome.rpcFailure # Constructor refusal cannot carry any listener result.
else: discard outcome.value # Defaults and missing-head alternatives contain no usable canonical owner.
