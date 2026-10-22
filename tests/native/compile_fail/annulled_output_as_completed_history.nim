# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"PreparedAccumulationOutputs","early":["outputsInfo(","[1] expected: PreparedAccumulationOutputs but got: PreparedAnnulmentOutputs"]}

## A parallel-entry selected pair set cannot impersonate completed round or block-history provenance.
import ../../../src/state/[accumulation_annulled_outputs, accumulation_outputs]
discard outputsInfo(default(PreparedAnnulmentOutputs))
