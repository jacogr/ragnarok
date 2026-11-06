# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native callback ownership cannot be duplicated by copying its enclosing transport value.
# @@Verification={"group":"ownership_compile","expected":"'=dup' is not available for type <Transport>","build_name":"quic-transport-copy","rationale":"The bridge retains the original Transport address as callback context; copying its native engine splits teardown authority and leaves callbacks pointing into a different owner.","reference":"src/quic/transport.nim"}
import ../../../src/quic/transport
var original = default(Transport)
var duplicate = original
original.closeTransport() # Preserve original use after the copy so the compiler cannot replace it with a sink.
duplicate.closeTransport()
