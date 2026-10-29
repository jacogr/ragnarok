# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "privacy", "expected": "info"}

## Callers cannot forge source-bound selected authority or mutate private results.
import ../../../src/state/service/supervision as service_supervision
var value = default(ServiceSupervision)
discard value.info
