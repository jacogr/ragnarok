# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Artifact callers cannot replace the retained import catalog.
# @@Verification={"group": "privacy", "expected": "imports"}
import ../../../src/pvm/artifact
let captured = default(Artifact)
discard captured.imports
