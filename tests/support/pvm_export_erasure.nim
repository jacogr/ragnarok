# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Execute original normalized export cases before constructing their bundle erasure owner.

import ../../src/state/bundle_erasure
import ../../src/state/erasure/[layout as erasure_layout, words as erasure_words]
import ../../src/state/[auditable_bundle, input_refinement]
import "../../src/state/export/erasure" as export_erasure
import ../../src/codec/bounded
import ../../src/codec/work/report as work_report
import ./[pvm_input_refinement, pvm_report_results, pvm_export_commitment, pvm_refinement_outcome]

proc exportErasureLimits*(): ExportErasureLimits =
  ## Separate finite output/work caps from the original tree/hash budgets.
  ExportErasureLimits(bytes: ByteLimit(1000000), products: FieldProductLimit(20000000),
      commitment: commitmentLimits())
proc exportBundle*(kind: int, shards = 1023'u16): BundleErasure =
  ## Select genuine successful, missing-code and panic executions; kind 65 crosses the proof-page boundary.
  let halt = @[50'u8, 0]
  let prefix = @[refinementImmediate(7, 65536), refinementImmediate(8, 3), @[10'u8, 8]]
  let good = reportGuest([prefix[0], prefix[1], prefix[2], refinementImmediate(8, 0), halt], declared = 1)
  let missing = reportGuest([halt], declared = 1, missing = true)
  let panic = reportGuest([prefix[0], prefix[1], prefix[2], @[0'u8]], declared = 1)
  var guests: seq[ReportGuest] = @[]
  case kind
  of 0: guests = @[reportGuest([refinementImmediate(8, 0), halt])] # A genuine successful zero-export report.
  of 1: guests = @[good] # Successful exported bytes are 11/12/13 followed by fixed-width zero padding.
  of 3: guests = @[good, missing, panic] # Final normalized exports discard both rejected actual outputs.
  else: guests = @[reportGuest([halt], declared = uint64(kind),
      missing = true)] # Protocol normalization synthesizes zeros.
  let fixture = executionFixture([halt], guests, external = false)
  let execution = executionRun(fixture).value
  let bundle = prepareAuditableBundle(execution, ByteLimit(4096)).value
  let layout = prepareErasureLayout(bundle, ErasureShards(shards), ByteLimit(8192)).value
  prepareBundleErasure(layout, BundleErasureLimits(bytes: ByteLimit(20000),
      products: FieldProductLimit(2000000))).value
