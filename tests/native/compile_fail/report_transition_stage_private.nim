# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge atomic block/report success or unrelated failure causes.
import ../../../src/state/report_transition
let result = default(BlockReportResult)
discard result.stageReason # Private field access must fail before lowering.
