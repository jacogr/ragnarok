# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "got: ByteLimit but wanted: ElementLimit"}

## Work and core identities cannot alias wire extents or source owners.
import ../../../src/state/accumulation/global/roles as accumulation_global_roles
import ../../../src/state/accumulation/annulment as accumulation_annulment
import ../../../src/codec/bounded
import ../../../src/codec/state/privileges as state_privileges
discard AccumulationGlobalRoleLimits(outcomes: ByteLimit(1))
