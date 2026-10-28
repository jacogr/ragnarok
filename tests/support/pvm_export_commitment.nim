# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Genuine source-bound report fixtures for export roots and proof-page witnesses.

import ../../src/state/export_commitment as state_export_commitment
import ../../src/state/report_identity as state_report_identity
import ../../src/state/authorized_refinement as state_authorized_refinement
import ../../src/codec/bounded as codec_bounded
import ./pvm_authorized_refinement
import ./pvm_report_identity
import ./pvm_report_results

proc commitmentLimits*(): ExportCommitmentLimits =
  ## Finite ceilings admit every GP export count, padded tree and exact hash preimage workload.
  ExportCommitmentLimits(exports: ElementLimit(3072), nodes: ElementLimit(8192),
      hashBytes: ByteLimit(13000000))
proc commitmentSource*(guests: openArray[ReportGuest]): ReportIdentity =
  ## Execute original authorization and normalized refinement before any commitment is requested.
  let source = authorizedFixture([@[50'u8, 0]], guests)
  let completed = prepareAuthorizedRefinement(source.authorization, source.inputs, authorizedLimits()).value
  prepareReportIdentity(completed, [], identityLimits()).value
proc zeroExportSource*(count: uint64): ReportIdentity =
  ## Missing code gives raw BAD; I selects BadExports for positive declarations and synthesizes exactly that many zeros.
  commitmentSource([reportGuest([@[50'u8, 0]], declared = count, missing = true)])
