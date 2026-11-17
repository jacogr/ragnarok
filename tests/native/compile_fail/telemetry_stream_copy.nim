# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A copied scalar mailbox owner could join and free storage still owned by another stream.

# @@Verification={"group":"ownership_compile","expected":"'=dup' is not available for type <TelemetryStream>","build_name":"nimony-telemetry-stream-copy","rationale":"A scalar-only mailbox owner must not duplicate task join and deallocation authority.","reference":"spec/telemetry.md"}

import ../../../src/telemetry/stream

var original = default(TelemetryStream)
var duplicate = original
original.close()
duplicate.close()
