# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Unchecked callers cannot select or rewrite result payloads or nested reasons.
# @@Verification={"group": "privacy", "expected": "identityReason"}
import ../../../src/app/checkpoint_codec as app_checkpoint_codec
let outcome = default(ApplicationCheckpointResult[seq[byte]])
discard outcome.identityReason
