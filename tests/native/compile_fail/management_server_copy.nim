# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Management descriptor owners cannot be duplicated by aggregate assignment.

# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <ManagementServer>", "build_name": "management-server-copy"}

import ../../../src/management/server as management_server
var original = default(ManagementServer)
var duplicate = original
original.close() # Original use prevents last-use sinking from hiding a copy.
duplicate.close()
