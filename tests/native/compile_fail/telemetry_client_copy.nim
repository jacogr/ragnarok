# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The composite exporter must independently refuse duplication of its nested live task owner.

# @@Verification={"group":"ownership_compile","expected":"'=dup' is not available for type <Client>","build_name":"nimony-telemetry-client-copy","rationale":"Copying the composite exporter would duplicate nested mailbox cleanup and event-stream authority.","reference":"spec/telemetry.md"}

import ../../../src/telemetry/client

var original = default(Client)
var duplicate = original
original.close()
duplicate.close()
