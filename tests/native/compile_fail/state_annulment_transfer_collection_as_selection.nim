# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group":"nominal","expected":"PreparedAccumulationAnnulment","early":["prepareAnnulmentTransfers(","[1] expected: PreparedAccumulationAnnulment but got: PreparedAccumulationTransfers"]}

## A raw transfer collection cannot substitute the genuine common-source conflict certificate.
import ../../../src/state/accumulation_transfers as state_accumulation_transfers
discard prepareAnnulmentTransfers(default(PreparedAccumulationTransfers),
    AccumulationTransferCollectionLimits())
