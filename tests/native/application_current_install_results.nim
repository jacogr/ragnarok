# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default current updates cannot install canonical/RPC state or acknowledge a fabricated child.
import std/cmdline
import ../../src/app/chain
import ../../src/rpc/server
import ../../src/state/accumulation/current/update as accumulation_current_update
var owner = default(ApplicationChain)
var rpc = default(Server)
let prepared = default(PreparedCurrentChainUpdate)
case paramStr(1)
of "rpc": owner.installPrepared(rpc, prepared) # Open/history/lease/current readiness is mandatory.
of "acknowledge": discard owner.installedPrepared(prepared) # Exact installed candidate identity is mandatory.
else: owner.installPrepared(prepared) # Default current readiness cannot authorize canonical replacement.
