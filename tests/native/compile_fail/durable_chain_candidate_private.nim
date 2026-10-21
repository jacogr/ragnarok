# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A caller cannot replace the candidate carried by a prepared publication certificate.
# @@Verification={"group":"privacy","expected":"state"}
import ../../../src/state/accumulation_publication
var prepared = default(PreparedChainUpdate)
discard prepared.state
