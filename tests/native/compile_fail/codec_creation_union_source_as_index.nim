# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"expected: AccumulationCreationIndex but got: PreparedAccumulationAnnulment","early":["createdAccountAt(","[2] expected: AccumulationCreationIndex but got: PreparedAccumulationAnnulment"]}

## Account positions and element limits cannot alias source owners or byte extents.
import ../../../src/state/accumulation_creation_union as state_accumulation_creation_union
import ../../../src/state/accumulation_annulment as state_accumulation_annulment
import ../../../src/codec/bounded as codec_bounded
discard createdAccountAt(default(PreparedAccumulationCreationUnion), default(PreparedAccumulationAnnulment))
