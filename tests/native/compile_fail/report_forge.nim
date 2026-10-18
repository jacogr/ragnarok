# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Safe code cannot bypass the private report state through status.
import ../../../src/codec/[composite, work_report, report_owned]
var value = default(ReportResult)
discard ReportResult(status: CompositeError.None)
