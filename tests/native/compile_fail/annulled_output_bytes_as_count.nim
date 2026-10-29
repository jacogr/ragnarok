# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"got: ByteLimit but wanted: ElementLimit"}

## Original outcome inspection counts producers, not encoded byte payload.
import ../../../src/state/accumulation/annulled_outputs as accumulation_annulled_outputs
import ../../../src/codec/bounded
discard AnnulmentOutputLimits(outcomes: ByteLimit(1))
