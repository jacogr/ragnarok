# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "got: ByteLimit but wanted: ElementLimit"}

## Work and core identities cannot alias wire extents or source owners.
import ../../../src/state/accumulation_global_roles as state_accumulation_global_roles
import ../../../src/state/accumulation_annulment as state_accumulation_annulment
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_privileges as codec_state_privileges
discard AccumulationGlobalRoleLimits(outcomes: ByteLimit(1))
