# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "privacy", "expected": "status"}

## Callers cannot forge success or mutate retained parser/batch storage.
import "../../../src/jamnp-s/audits"
var result = default(AuditResult[JudgmentBatch])
result.status = AuditError.None
