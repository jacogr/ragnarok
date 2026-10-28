# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Artifact failures cannot expose a fabricated completed owner.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/pvm/artifact
let answer = default(ArtifactResult[Artifact])
discard answer.completed
