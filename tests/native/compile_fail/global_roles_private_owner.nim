# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "data"}

## Role certificates keep retained owner and tagged storage private.
import ../../../src/state/accumulation/global/roles as accumulation_global_roles
import ../../../src/state/accumulation/annulment as accumulation_annulment
discard default(PreparedAccumulationGlobalRoles).data
