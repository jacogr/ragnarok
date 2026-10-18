# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot forge atomic block/report success or unrelated failure causes.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/state/report_transition
let result = default(BlockReportResult)
discard result.publicationReason # Private field access must fail before lowering.
