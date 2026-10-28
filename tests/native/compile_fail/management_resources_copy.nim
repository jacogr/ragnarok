# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Management descriptor owners cannot be duplicated by aggregate assignment.

# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <ResourceSampler>", "build_name": "management-resources-copy"}

import ../../../src/management/resources as management_resources
var original = default(ResourceSampler)
var duplicate = original
original.close() # Original use prevents last-use sinking from hiding a copy.
duplicate.close()
