# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit test-only finite report/availability budgets reuse independently exercised component policies.
import ../../src/jamnp-s/work_report
import ../../src/codec/bounded
import ../../src/state/bundle_erasure
import ../../src/state/erasure/words
import ./[pvm_export_erasure, pvm_computed_report]
proc workReportLimits*(): WorkReportLimits =
  ## Small genuine imported bundles and six-validator encodings fit without selecting any production defaults.
  WorkReportLimits(bundleBytes: ByteLimit(20000), layoutBytes: ByteLimit(20000),
    reportBytes: ByteLimit(20000), transcriptBytes: ByteLimit(21000),
    bundle: BundleErasureLimits(bytes: ByteLimit(1000000), products: FieldProductLimit(10000000)),
    exports: exportErasureLimits(), availability: reportAvailabilityLimits())
