# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "info"}

## Source, policies and tagged payload storage remain private and cannot be substituted externally.
import ../../../src/app/logical/service_proof as logical_service_proof
let source = default(LogicalServiceProof)
discard source.info
