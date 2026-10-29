# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"PreparedAccumulationOutputs","early":["outputsInfo(","[1] expected: PreparedAccumulationOutputs but got: PreparedAnnulmentOutputs"]}

## A parallel-entry selected pair set cannot impersonate completed round or block-history provenance.
import ../../../src/state/accumulation/[annulled_outputs as accumulation_annulled_outputs,
    outputs as accumulation_outputs]
discard outputsInfo(default(PreparedAnnulmentOutputs))
