# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## New seed failure reasons remain selected; defaults/refusals never expose a configured owner.

import std/cmdline
import ../../src/app/chain
import ../../src/chain/[provider, genesis]

let argument = paramStr(1)
let outcome = if argument == "default": default(ApplicationChainResult[ApplicationChain])
  elif argument == "refused": initApplicationChain("{}", genesisStoreLimits())
  else: initApplicationChain(default(ChainView))
case argument
of "parameters": discard outcome.parametersError # Missing-head refusal did not select parameter decoding.
of "genesis": discard outcome.genesisFailure # Missing-head refusal did not select configured capture.
else: discard outcome.value # Neither default nor bad configured parameters contains a seed owner.
