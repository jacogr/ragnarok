# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A package identity cannot be initialized with an exported-segment commitment.
import ../../../src/codec/work_report
let wrong = ReportHeader(packageHash: SegmentRoot())
discard wrong
